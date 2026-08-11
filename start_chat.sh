#!/bin/bash
# Avvia llama-server + SearXNG + Open WebUI e apre il browser
# con la chat Qwen3 8B (ricerca web attiva via SearXNG).

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$HOME/Scrivania/owui.env"
SEARXNG_DIR="$HOME/Scrivania/searxng"
LOG_DIR="$DIR/logs"
VENV="$DIR/venv"
DATA_DIR="$HOME/Scrivania/openwebui/data"

BASE_MODEL="models/Qwen3-8B-Q4_K_M.gguf"
CUSTOM_MODEL_ID="qwen3-web"
OWUI_PORT=3000
LLAMA_PORT=8080

mkdir -p "$LOG_DIR"
cd "$DIR"

[ -f "$ENV_FILE" ] || { echo "Manca $ENV_FILE"; exit 1; }
set -a
. "$ENV_FILE"
set +a

echo "==> Avvio servizi..."

# --- SearXNG (meta-search, porta 8888) ---
if pgrep -f "[s]earx.webapp" > /dev/null; then
  echo "  [ok] SearXNG gia' attivo"
else
  SEARXNG_SETTINGS_PATH="$SEARXNG_DIR/settings.yml" \
    setsid "$VENV/bin/python" -m searx.webapp > "$LOG_DIR/searxng.log" 2>&1 < /dev/null &
  echo "  [..] SearXNG avviato (http://localhost:8888)"
fi

# --- llama-server (modello Qwen3 8B, porta 8080) ---
if curl -s -m 2 -o /dev/null "http://localhost:$LLAMA_PORT/health"; then
  echo "  [ok] llama-server gia' attivo"
else
  setsid ./build/bin/llama-server \
    -m "$BASE_MODEL" \
    -ngl 99 \
    -c 16384 \
    -n 2048 \
    -ctk q8_0 \
    -ctv q8_0 \
    --reasoning off \
    --host 0.0.0.0 \
    --port "$LLAMA_PORT" > "$LOG_DIR/llama-server.log" 2>&1 < /dev/null &
  echo "  [..] llama-server avviato (attendo il caricamento del modello...)"
fi

# --- Open WebUI (porta 3000) ---
if pgrep -f "[o]pen-webui serve" > /dev/null; then
  echo "  [ok] Open WebUI gia' attivo"
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
  echo "  [..] Open WebUI avviato"
fi

echo "==> Attendo i servizi..."

for i in $(seq 1 90); do
  curl -s -m 2 -o /dev/null "http://localhost:$OWUI_PORT" && break
  sleep 2
done
curl -s -m 2 -o /dev/null "http://localhost:$OWUI_PORT" || { echo "ERRORE: Open WebUI non risponde (vedi logs/openwebui.log)"; exit 1; }
echo "  [ok] Open WebUI pronto"

for i in $(seq 1 120); do
  curl -s -m 2 -o /dev/null "http://localhost:$LLAMA_PORT/health" && break
  sleep 2
done
if curl -s -m 2 -o /dev/null "http://localhost:$LLAMA_PORT/health"; then
  echo "  [ok] llama-server pronto"
else
  echo "  [warn] llama-server non pronto (vedi logs/llama-server.log)"
fi

echo "==> Configuro il modello con web search attivo (idempotente)..."

TOKEN=$(curl -s -m 10 -X POST "http://localhost:$OWUI_PORT/api/v1/auths/signin" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$WEBUI_ADMIN_EMAIL\",\"password\":\"$WEBUI_ADMIN_PASSWORD\"}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || true)

if [ -z "$TOKEN" ]; then
  echo "  [warn] login admin fallito - configura manualmente il web search in Open WebUI"
else
  AUTH="Authorization: Bearer $TOKEN"

  # 1) collega llama.cpp (se non gia' presente)
  if ! curl -s -m 10 "http://localhost:$OWUI_PORT/openai/config" -H "$AUTH" \
    | python3 -c "import json,sys; print('http://localhost:'+sys.argv[1]+'/v1' in json.load(sys.stdin).get('OPENAI_API_BASE_URLS',[]))" "$LLAMA_PORT" 2>/dev/null | grep -q True; then
    curl -s -m 15 -X POST "http://localhost:$OWUI_PORT/openai/config/update" -H "$AUTH" \
      -H "Content-Type: application/json" \
      -d "{\"ENABLE_OPENAI_API\":true,\"OPENAI_API_BASE_URLS\":[\"http://localhost:$LLAMA_PORT/v1\"],\"OPENAI_API_KEYS\":[\"\"],\"OPENAI_API_CONFIGS\":{\"0\":{\"provider\":\"llama.cpp\",\"enable\":true,\"prefix_id\":null}}}" > /dev/null
    echo "  [..] connessione llama.cpp aggiunta"
  else
    echo "  [ok] connessione llama.cpp presente"
  fi

  # 2) crea il modello "qwen3-web" con web search di default (se assente)
  if [ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' "http://localhost:$OWUI_PORT/api/v1/models/model?id=$CUSTOM_MODEL_ID" -H "$AUTH")" = "200" ]; then
    echo "  [ok] modello $CUSTOM_MODEL_ID gia' configurato"
  else
    curl -s -m 15 -X POST "http://localhost:$OWUI_PORT/api/v1/models/create" -H "$AUTH" \
      -H "Content-Type: application/json" \
      -d "{\"id\":\"$CUSTOM_MODEL_ID\",\"base_model_id\":\"$BASE_MODEL\",\"name\":\"Qwen3 8B (Web)\",\"params\":{\"function_calling\":\"legacy\"},\"meta\":{\"defaultFeatureIds\":[\"web_search\"],\"capabilities\":{\"web_search\":true},\"description\":\"Qwen3 8B con ricerca web attiva\"},\"access_grants\":[],\"is_active\":true}" > /dev/null
    echo "  [..] modello $CUSTOM_MODEL_ID creato"
  fi

  # 2b) crea i modelli di riserva "ornith-web" e "qwen-web" (se assenti)
  #     richiedono che llama-server sia riavviato con il modello relativo
  ORNITH_MODEL_ID="ornith-web"
  ORNITH_BASE_MODEL="models/ornith-1.0-9b-Q4_K_M.gguf"
  if [ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' "http://localhost:$OWUI_PORT/api/v1/models/model?id=$ORNITH_MODEL_ID" -H "$AUTH")" = "200" ]; then
    echo "  [ok] modello $ORNITH_MODEL_ID gia' configurato"
  else
    curl -s -m 15 -X POST "http://localhost:$OWUI_PORT/api/v1/models/create" -H "$AUTH" \
      -H "Content-Type: application/json" \
      -d "{\"id\":\"$ORNITH_MODEL_ID\",\"base_model_id\":\"$ORNITH_BASE_MODEL\",\"name\":\"Ornith 9B (Web)\",\"params\":{\"function_calling\":\"legacy\"},\"meta\":{\"defaultFeatureIds\":[\"web_search\"],\"capabilities\":{\"web_search\":true},\"description\":\"Ornith 9B con ricerca web attiva (modello di riserva)\"},\"access_grants\":[],\"is_active\":true}" > /dev/null
    echo "  [..] modello $ORNITH_MODEL_ID creato"
  fi
  QWEN_MODEL_ID="qwen-web"
  QWEN_BASE_MODEL="models/qwen2.5-7b-instruct-q4_k_m.gguf"
  if [ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' "http://localhost:$OWUI_PORT/api/v1/models/model?id=$QWEN_MODEL_ID" -H "$AUTH")" = "200" ]; then
    echo "  [ok] modello $QWEN_MODEL_ID gia' configurato"
  else
    curl -s -m 15 -X POST "http://localhost:$OWUI_PORT/api/v1/models/create" -H "$AUTH" \
      -H "Content-Type: application/json" \
      -d "{\"id\":\"$QWEN_MODEL_ID\",\"base_model_id\":\"$QWEN_BASE_MODEL\",\"name\":\"Qwen 7B (Web)\",\"params\":{\"function_calling\":\"legacy\"},\"meta\":{\"defaultFeatureIds\":[\"web_search\"],\"capabilities\":{\"web_search\":true},\"description\":\"Qwen 2.5 7B con ricerca web attiva\"},\"access_grants\":[],\"is_active\":true}" > /dev/null
    echo "  [..] modello $QWEN_MODEL_ID creato"
  fi

  # 3) ricarica la cache dei modelli cosi' "Qwen3 8B (Web)" compare in UI
  curl -s -m 15 "http://localhost:$OWUI_PORT/api/v1/models" -H "$AUTH" > /dev/null
fi

echo "==> Apro il browser..."
URL="http://localhost:$OWUI_PORT"
xdg-open "$URL" > /dev/null 2>&1 || sensible-browser "$URL" > /dev/null 2>&1 || true

echo
echo "Fatto. Scegli il modello \"Qwen3 8B (Web)\" nella chat."
echo "Il web search e' attivo di default: il modello cerca da solo sul web."
