# AGENTS.md - session memory

Setup of a local AI assistant (llama.cpp + Open WebUI + SearXNG) on a laptop
with AMD Radeon 680M (Vulkan/RADV), 16 GB RAM, Debian.

## Status reached (Aug 2026)

Everything works and is verified end-to-end:
- llama.cpp built Release with Vulkan ON (commit 15586e2d7, 2026-08-06)
- GPU detected: `AMD Radeon Graphics (RADV REMBRANDT)` (UMA)
- Main model: Qwen3-8B-Q4_K_M.gguf (4.7 GB), thinking disabled via
  `--reasoning off`
- llama-server as a **multi-model router**: `--models-dir models --models-max 1`
  (one model in RAM at a time, LRU)
- Open WebUI 0.11.0 with working web search ("*-web" models,
  `function_calling: legacy` + `capabilities.web_search: true`)
- SearXNG on port 8888, Open WebUI 3000, llama-server 8080
- LAN access verified: `http://<server-IP>:3000`

## Paths (on this machine: `$HOME=/home/debian`)

| What | Path |
|---|---|
| llama.cpp (repo + build) | `$HOME/Scrivania/llama.cpp` |
| Python venv | `$HOME/Scrivania/llama.cpp/venv` |
| models | `$HOME/Scrivania/llama.cpp/models/` |
| service logs | `$HOME/Scrivania/llama.cpp/logs/` |
| start script | `$HOME/Scrivania/llama.cpp/start_chat.sh` (everything: services + web search config + browser) |
| Open WebUI data | `$HOME/Scrivania/openwebui/data` (webui.db) |
| admin credentials | `$HOME/Scrivania/owui.env` (DO NOT commit; `.env.example` shows the format) |
| SearXNG | `$HOME/Scrivania/searxng`, settings in `settings.yml` |
| repo docs | `$HOME/Scrivania/llama-local-ai` (this repo) |

## Useful commands

```bash
# full start (all services + browser)
$HOME/Scrivania/llama.cpp/start_chat.sh

# daemonized llama server (multi-model router)
cd $HOME/Scrivania/llama.cpp && setsid ./build/bin/llama-server \
  --models-dir models --models-max 1 -ngl 99 -c 16384 -n 2048 -ctk q8_0 -ctv q8_0 \
  --reasoning off --host 0.0.0.0 --port 8080 > logs/llama-server.log 2>&1 < /dev/null &

# service status
curl -s -o /dev/null -w "llama %{http_code}\n" http://localhost:8080/health
curl -s -o /dev/null -w "owui  %{http_code}\n" http://localhost:3000
pgrep -f "searx.webapp"    # SearXNG
systemctl --user status owui-compact.service   # Open WebUI (if started via systemd-run)
```

## Key configuration

- llama-server: `--models-dir models --models-max 1 -ngl 99 -c 16384 -n 2048 -ctk q8_0 -ctv q8_0 --reasoning off --host 0.0.0.0 --port 8080`
- Open WebUI env: `DATA_DIR`, `ENABLE_WEB_SEARCH=true`, `WEB_SEARCH_ENGINE=searxng`,
  `SEARXNG_QUERY_URL=http://localhost:8888/search`, `ENABLE_CONTEXT_COMPACTION=true`,
  `CONTEXT_COMPACTION_TOKEN_THRESHOLD=12000`, `CONTEXT_COMPACTION_RETENTION_PERCENTAGE=30`
- Working web search = Open WebUI model with:
  `params.function_calling=legacy`, `meta.capabilities.web_search=true`,
  `meta.defaultFeatureIds=["web_search"]`
- Qwen3 is a reasoning model: without `--reasoning off` it burns tokens in
  "thinking" (you see `reasoning_content` in the response)
- SearXNG `settings.yml` must have `search.formats: [html, json]`, otherwise
  Open WebUI web search silently fails

## Known pitfalls (lessons learned)

1. **Open WebUI requires Python <3.13.** Debian 13 ships only Python 3.13, so
   `pip install open-webui` on the system python fails with "No matching
   distribution found". Must use Python 3.12 via pyenv:
   `~/.pyenv/versions/3.12.13/bin/python3 -m venv venv`. (`shaderc` is also not
   a Debian package: the binary is `glslc`.)
2. **The bash tool kills background processes on timeout.** For long-lived
   services use `setsid ... & echo started` AS THE LAST command of the call
   (no `sleep`/`pgrep` afterwards, otherwise the tool kill takes them down).
   Reliable alternative for Open WebUI: `systemd-run --user --unit=...`.
2. **`pkill -f '[l]lama-server'` kills itself**: the pattern also matches the
   shell running it (the command contains the string "llama-server").
   Use `kill $(pgrep -f '[l]lama-server' | grep -v bash)` or no kill at all if
   the process is not running.
3. `--chat-template-kwargs '{"enable_thinking":false}'` is DEPRECATED: use
   `--reasoning off` (warning in the log otherwise).
4. The repo `gguf-py` reads GGUF v3 metadata badly (wrong values): to validate a
   model you must load it with llama-server/llama-bench.
5. Interrupted downloads = truncated, unusable GGUF. Resume with `curl -L -C -`.
   DeepSeek-R1-Distill-Qwen-7B at 370 MB is broken, do not use it.
6. `systemctl --user` requires the systemd user manager; the host shell is
   `/bin/bash` (not zsh).

## Ports and services

| Port | Service | Scope |
|---|---|---|
| 8080 | llama-server | LAN (0.0.0.0) |
| 3000 | Open WebUI | LAN (0.0.0.0) |
| 8888 | SearXNG | localhost only (127.0.0.1) |
| 11434 | Ollama | not used (ignore connection errors) |

## Possible next steps

- Add more models to `models/` (the router exposes them automatically)
- Backup `webui.db` (chats and configured models)
