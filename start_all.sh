#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$DIR/logs"
mkdir -p "$LOG_DIR"
cd "$DIR"
set -a
. "$HOME/Scrivania/owui.env"
set +a

# 1. SearXNG (meta-search, porta 8888)
if pgrep -f "searx.webapp" > /dev/null; then
  echo "[ok] SearXNG gia' attivo"
else
  SEARXNG_SETTINGS_PATH="$HOME/Scrivania/searxng/settings.yml" \
    "$DIR/venv/bin/python" -m searx.webapp > "$LOG_DIR/searxng.log" 2>&1 &
  echo "[..] SearXNG avviato su http://localhost:8888"
fi

# 2. Open WebUI (porta 3000)
if pgrep -f "open-webui serve" > /dev/null; then
  echo "[ok] Open WebUI gia' attivo"
else
  DATA_DIR="$HOME/Scrivania/openwebui/data" \
  ENABLE_WEB_SEARCH=true \
  WEB_SEARCH_ENGINE=searxng \
  SEARXNG_QUERY_URL=http://localhost:8888/search \
  "$DIR/venv/bin/open-webui" serve --host 0.0.0.0 --port 3000 > "$LOG_DIR/openwebui.log" 2>&1 &
  echo "[..] Open WebUI avviato su http://localhost:3000"
fi

# 3. llama-server (in foreground)
exec ./build/bin/llama-server \
  -m models/Qwen3-8B-Q4_K_M.gguf \
  -ngl 99 \
  -c 16384 \
  -n 2048 \
  -ctk q8_0 \
  -ctv q8_0 \
  --reasoning off \
  --host 0.0.0.0 \
  --port 8080
