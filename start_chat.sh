#!/bin/bash
# Start llama-server + SearXNG + Open WebUI and open the browser
# with the Qwen3 8B chat (web search enabled via SearXNG).

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$HOME/Scrivania/owui.env"
SEARXNG_DIR="$HOME/Scrivania/searxng"
LOG_DIR="$DIR/logs"
VENV="$DIR/venv"
DATA_DIR="$HOME/Scrivania/openwebui/data"

MODEL_ALIAS="Qwen3-8B-Q4_K_M"
CUSTOM_MODEL_ID="qwen3-web"
OWUI_PORT=3000
LLAMA_PORT=8080

mkdir -p "$LOG_DIR"
cd "$DIR"

[ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE"; exit 1; }
set -a
. "$ENV_FILE"
set +a

echo "==> Starting services..."

# --- SearXNG (meta-search, port 8888) ---
if pgrep -f "[s]earx.webapp" > /dev/null; then
  echo "  [ok] SearXNG already running"
else
  SEARXNG_SETTINGS_PATH="$SEARXNG_DIR/settings.yml" \
    setsid "$VENV/bin/python3" -m searx.webapp > "$LOG_DIR/searxng.log" 2>&1 < /dev/null &
  echo "  [..] SearXNG started (http://localhost:8888)"
fi

# --- llama-server (multi-model router, port 8080) ---
# NB: --models-max 1: when switching models (Open WebUI) the previous one is
# unloaded (LRU), so only one model stays in RAM
if curl -s -m 2 -o /dev/null "http://localhost:$LLAMA_PORT/health"; then
  echo "  [ok] llama-server already running"
else
  setsid ./build/bin/llama-server \
    --models-dir models \
    --models-max 1 \
    -ngl 99 \
    -c 16384 \
    -n 2048 \
    -ctk q8_0 \
    -ctv q8_0 \
    --reasoning off \
    --host 0.0.0.0 \
    --port "$LLAMA_PORT" > "$LOG_DIR/llama-server.log" 2>&1 < /dev/null &
  echo "  [..] llama-server started (waiting for model load...)"
fi

# --- Open WebUI (port 3000) ---
if pgrep -f "[o]pen-webui serve" > /dev/null; then
  echo "  [ok] Open WebUI already running"
else
  DATA_DIR="$DATA_DIR" \
  ENABLE_WEB_SEARCH=true \
  WEB_SEARCH_ENGINE=searxng \
  SEARXNG_QUERY_URL=http://localhost:8888/search \
  ENABLE_CONTEXT_COMPACTION=true \
  CONTEXT_COMPACTION_TOKEN_THRESHOLD=12000 \
  CONTEXT_COMPACTION_RETENTION_PERCENTAGE=30 \
  setsid "$VENV/bin/open-webui" serve --host 0.0.0.0 --port "$OWUI_PORT" \
    > "$LOG_DIR/openwebui.log" 2>&1 < /dev/null &
  echo "  [..] Open WebUI started"
fi

echo "==> Waiting for services..."

for i in $(seq 1 90); do
  curl -s -m 2 -o /dev/null "http://localhost:$OWUI_PORT" && break
  sleep 2
done
curl -s -m 2 -o /dev/null "http://localhost:$OWUI_PORT" || { echo "ERROR: Open WebUI not responding (see logs/openwebui.log)"; exit 1; }
echo "  [ok] Open WebUI ready"

for i in $(seq 1 120); do
  curl -s -m 2 -o /dev/null "http://localhost:$LLAMA_PORT/health" && break
  sleep 2
done
if curl -s -m 2 -o /dev/null "http://localhost:$LLAMA_PORT/health"; then
  echo "  [ok] llama-server ready"
else
  echo "  [warn] llama-server not ready (see logs/llama-server.log)"
fi

echo "==> Configuring model with web search enabled (idempotent)..."

TOKEN=$(curl -s -m 10 -X POST "http://localhost:$OWUI_PORT/api/v1/auths/signin" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$WEBUI_ADMIN_EMAIL\",\"password\":\"$WEBUI_ADMIN_PASSWORD\"}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || true)

if [ -z "$TOKEN" ]; then
  echo "  [warn] admin login failed - configure web search manually in Open WebUI"
else
  AUTH="Authorization: Bearer $TOKEN"

  # 1) connect llama.cpp (if not already present)
  if ! curl -s -m 10 "http://localhost:$OWUI_PORT/openai/config" -H "$AUTH" \
    | python3 -c "import json,sys; print('http://localhost:'+sys.argv[1]+'/v1' in json.load(sys.stdin).get('OPENAI_API_BASE_URLS',[]))" "$LLAMA_PORT" 2>/dev/null | grep -q True; then
    curl -s -m 15 -X POST "http://localhost:$OWUI_PORT/openai/config/update" -H "$AUTH" \
      -H "Content-Type: application/json" \
      -d "{\"ENABLE_OPENAI_API\":true,\"OPENAI_API_BASE_URLS\":[\"http://localhost:$LLAMA_PORT/v1\"],\"OPENAI_API_KEYS\":[\"\"],\"OPENAI_API_CONFIGS\":{\"0\":{\"provider\":\"llama.cpp\",\"enable\":true,\"prefix_id\":null}}}" > /dev/null
    echo "  [..] llama.cpp connection added"
  else
    echo "  [ok] llama.cpp connection present"
  fi

  # 2) create the "qwen3-web" model with web search by default (if missing)
  if [ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' "http://localhost:$OWUI_PORT/api/v1/models/model?id=$CUSTOM_MODEL_ID" -H "$AUTH")" = "200" ]; then
    echo "  [ok] model $CUSTOM_MODEL_ID already configured"
  else
    curl -s -m 15 -X POST "http://localhost:$OWUI_PORT/api/v1/models/create" -H "$AUTH" \
      -H "Content-Type: application/json" \
      -d "{\"id\":\"$CUSTOM_MODEL_ID\",\"base_model_id\":\"$MODEL_ALIAS\",\"name\":\"Qwen3 8B (Web)\",\"params\":{\"function_calling\":\"legacy\"},\"meta\":{\"defaultFeatureIds\":[\"web_search\"],\"capabilities\":{\"web_search\":true},\"description\":\"Qwen3 8B with web search enabled\"},\"access_grants\":[],\"is_active\":true}" > /dev/null
    echo "  [..] model $CUSTOM_MODEL_ID created"
  fi

  # 2b) create backup models "ornith-web" and "qwen-web" (if missing)
  #     they require llama-server to be restarted with the related model
  ORNITH_MODEL_ID="ornith-web"
  ORNITH_BASE_MODEL="ornith-1.0-9b-Q4_K_M"
  if [ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' "http://localhost:$OWUI_PORT/api/v1/models/model?id=$ORNITH_MODEL_ID" -H "$AUTH")" = "200" ]; then
    echo "  [ok] model $ORNITH_MODEL_ID already configured"
  else
    curl -s -m 15 -X POST "http://localhost:$OWUI_PORT/api/v1/models/create" -H "$AUTH" \
      -H "Content-Type: application/json" \
      -d "{\"id\":\"$ORNITH_MODEL_ID\",\"base_model_id\":\"$ORNITH_BASE_MODEL\",\"name\":\"Ornith 9B (Web)\",\"params\":{\"function_calling\":\"legacy\"},\"meta\":{\"defaultFeatureIds\":[\"web_search\"],\"capabilities\":{\"web_search\":true},\"description\":\"Ornith 9B with web search enabled (backup model)\"},\"access_grants\":[],\"is_active\":true}" > /dev/null
    echo "  [..] model $ORNITH_MODEL_ID created"
  fi
  QWEN_MODEL_ID="qwen-web"
  QWEN_BASE_MODEL="qwen2.5-7b-instruct-q4_k_m"
  if [ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' "http://localhost:$OWUI_PORT/api/v1/models/model?id=$QWEN_MODEL_ID" -H "$AUTH")" = "200" ]; then
    echo "  [ok] model $QWEN_MODEL_ID already configured"
  else
    curl -s -m 15 -X POST "http://localhost:$OWUI_PORT/api/v1/models/create" -H "$AUTH" \
      -H "Content-Type: application/json" \
      -d "{\"id\":\"$QWEN_MODEL_ID\",\"base_model_id\":\"$QWEN_BASE_MODEL\",\"name\":\"Qwen 7B (Web)\",\"params\":{\"function_calling\":\"legacy\"},\"meta\":{\"defaultFeatureIds\":[\"web_search\"],\"capabilities\":{\"web_search\":true},\"description\":\"Qwen 2.5 7B with web search enabled\"},\"access_grants\":[],\"is_active\":true}" > /dev/null
    echo "  [..] model $QWEN_MODEL_ID created"
  fi

  # 2c) Gemma models with web search (if missing)
  create_web_model() {
    local id="$1" base="$2" name="$3" desc="$4"
    if [ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' "http://localhost:$OWUI_PORT/api/v1/models/model?id=$id" -H "$AUTH")" = "200" ]; then
      echo "  [ok] model $id already configured"
    else
      curl -s -m 15 -X POST "http://localhost:$OWUI_PORT/api/v1/models/create" -H "$AUTH" \
        -H "Content-Type: application/json" \
        -d "{\"id\":\"$id\",\"base_model_id\":\"$base\",\"name\":\"$name\",\"params\":{\"function_calling\":\"legacy\"},\"meta\":{\"defaultFeatureIds\":[\"web_search\"],\"capabilities\":{\"web_search\":true},\"description\":\"$desc\"},\"access_grants\":[],\"is_active\":true}" > /dev/null
      echo "  [..] model $id created"
    fi
  }
  create_web_model "gemma3-web" "gemma-3-1b-it-Q4_K_M" "Gemma 3 1B (Web)" "Gemma 3 1B with web search enabled"
  create_web_model "gemma2-web" "gemma-2-9b-it-Q4_K_M" "Gemma 2 9B (Web)" "Gemma 2 9B with web search enabled"
  create_web_model "deepseek-web" "DeepSeek-V2-Lite-Chat.IQ2_S" "DeepSeek V2 Lite (Web)" "DeepSeek V2 Lite MoE with web search enabled"


  # 3) refresh the model cache so "Qwen3 8B (Web)" shows in the UI
  curl -s -m 15 "http://localhost:$OWUI_PORT/api/v1/models" -H "$AUTH" > /dev/null
fi

echo "==> Opening browser..."
URL="http://localhost:$OWUI_PORT"
xdg-open "$URL" > /dev/null 2>&1 || sensible-browser "$URL" > /dev/null 2>&1 || true

echo
echo "Done. Pick the \"Qwen3 8B (Web)\" model in the chat."
echo "Web search is enabled by default: the model searches the web on its own."
