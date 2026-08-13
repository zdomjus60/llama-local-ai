# AGENTS.md - memoria per la ripresa delle sessioni

Setup di un'assistente AI locale (llama.cpp + Open WebUI + SearXNG) su laptop
con AMD Radeon 680M (Vulkan/RADV), 16 GB RAM, Debian.

## Stato raggiunto (ago 2026)

Tutto funzionante e verificato end-to-end:
- llama.cpp compilato Release con Vulkan ON (commit 15586e2d7, 2026-08-06)
- GPU riconosciuta: `AMD Radeon Graphics (RADV REMBRANDT)` (UMA)
- Modello principale: Qwen3-8B-Q4_K_M.gguf (4,7 GB), thinking disattivato
  via `--reasoning off`
- llama-server come **router multi-modello**: `--models-dir models
  --models-max 1` (un solo modello in RAM alla volta, LRU)
- Open WebUI 0.11.0 con web search funzionante (modelli "*-web",
  `function_calling: legacy` + `capabilities.web_search: true`)
- SearXNG su porta 8888, Open WebUI 3000, llama-server 8080
- Accesso da LAN verificato: `http://<IP-del-server>:3000`

## Percorsi (in questa macchina: `$HOME=/home/debian`)

| Cosa | Percorso |
|---|---|
| llama.cpp (repo + build) | `$HOME/Scrivania/llama.cpp` |
| venv Python | `$HOME/Scrivania/llama.cpp/venv` |
| modelli | `$HOME/Scrivania/llama.cpp/models/` |
| log servizi | `$HOME/Scrivania/llama.cpp/logs/` |
| script di avvio | `$HOME/Scrivania/llama.cpp/start_chat.sh` (tutto: servizi + config web search + browser) |
| dati Open WebUI | `$HOME/Scrivania/openwebui/data` (webui.db) |
| credenziali admin | `$HOME/Scrivania/owui.env` (NON committare; `.env.example` per il formato) |
| SearXNG | `$HOME/Scrivania/searxng`, settings in `settings.yml` |
| documentazione repo | `$HOME/Scrivania/llama-setup` (questa) |

## Comandi utili

```bash
# avvio completo (tutti i servizi + browser)
$HOME/Scrivania/llama.cpp/start_chat.sh

# server llama daemonizzato (router multi-modello)
cd $HOME/Scrivania/llama.cpp && setsid ./build/bin/llama-server \
  --models-dir models --models-max 1 -ngl 99 -c 16384 -n 2048 -ctk q8_0 -ctv q8_0 \
  --reasoning off --host 0.0.0.0 --port 8080 > logs/llama-server.log 2>&1 < /dev/null &

# stato servizi
curl -s -o /dev/null -w "llama %{http_code}\n" http://localhost:8080/health
curl -s -o /dev/null -w "owui  %{http_code}\n" http://localhost:3000
pgrep -f "searx.webapp"    # SearXNG
systemctl --user status owui-compact.service   # Open WebUI (se avviato via systemd-run)
```

## Configurazioni chiave

- llama-server: `--models-dir models --models-max 1 -ngl 99 -c 16384 -n 2048 -ctk q8_0 -ctv q8_0 --reasoning off --host 0.0.0.0 --port 8080`
- Open WebUI env: `DATA_DIR`, `ENABLE_WEB_SEARCH=true`, `WEB_SEARCH_ENGINE=searxng`,
  `SEARXNG_QUERY_URL=http://localhost:8888/search`, `ENABLE_CONTEXT_COMPACTION=true`,
  `CONTEXT_COMPACTION_TOKEN_THRESHOLD=12000`, `CONTEXT_COMPACTION_RETENTION_PERCENTAGE=30`
- Web search funzionante = modello in Open WebUI con:
  `params.function_calling=legacy`, `meta.capabilities.web_search=true`,
  `meta.defaultFeatureIds=["web_search"]`
- Qwen3 e' reasoning model: senza `--reasoning off` brucia i token in "thinking"
  (si vede `reasoning_content` nella risposta)

## Insidie note (lezioni apprese)

1. **Il tool bash uccide i processi in background al timeout.** Per servizi
   longevi usare `setsid ... & echo avviato` COME ULTIMO comando della chiamata
   (niente `sleep`/`pgrep` dopo, altrimenti il kill del tool li abbatte).
   Alternativa affidabile per Open WebUI: `systemd-run --user --unit=...`.
2. **`pkill -f '[l]lama-server'` si uccide da solo**: il pattern matcha anche
   la shell che lo esegue (il comando contiene la stringa "llama-server").
   Usare `kill $(pgrep -f '[l]lama-server' | grep -v bash)` oppure niente kill
   se il processo non c'e'.
3. `--chat-template-kwargs '{"enable_thinking":false}'` e' DEPRECATO: usare
   `--reasoning off` (avviso nel log altrimenti).
4. `gguf-py` del repo legge male le metadata GGUF v3 (valori sballati): per
   validare un modello bisogna caricarlo con llama-server/llama-bench.
5. Download interrotti = GGUF troncato e inutilizzabile. Riprendere con
   `curl -L -C -`. DeepSeek-R1-Distill-Qwen-7B a 370 MB e' rotto, non usarlo.
6. `systemctl --user` richiede il manager systemd utente; il sistema host usa
   `/bin/bash` (non zsh).

## Porte e servizi

| Porta | Servizio | Scope |
|---|---|---|
| 8080 | llama-server | LAN (0.0.0.0) |
| 3000 | Open WebUI | LAN (0.0.0.0) |
| 8888 | SearXNG | solo localhost (127.0.0.1) |
| 11434 | Ollama | non usato (errori di connessione ignorabili) |

## Prossimi passi possibili

- Eventuali altri modelli da aggiungere a `models/` (il router li espone da solo)
- Backup di `webui.db` (chat e modelli configurati)
