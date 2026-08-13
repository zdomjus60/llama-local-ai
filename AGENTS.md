# AGENTS.md - session memory

Setup of a local AI assistant (llama.cpp + Open WebUI + SearXNG) on this
machine (Thinkpad, Debian 13, 32 GB DDR4, dual GPU: Intel UHD 620 iGPU +
AMD Radeon RX 580 / RADV).

## Status reached (Aug 2026)

- llama.cpp built Release with Vulkan ON
- Default model: **Qwen3-4B-Q4_K_M** (2.5 GB) - chosen because the RX 580
  (Polaris 2017) has very slow FP16: Qwen3-8B ran prompt processing at
  ~4.6 tok/s (minutes per question). 8B still available for stronger GPUs
  (see README note).
- llama-server as a multi-model router: `--models-dir models --models-max 1`
- Open WebUI 0.11.0 (venv), SearXNG on 8888, llama-server 8080
- **IMPORTANT on this machine**: a separate system-wide stack already exists
  (Open WebUI on :3000 as `uvicorn open_webui.main:app`, SearXNG under
  `/usr/local/searxng`, mcp_servers under `/app`). The venv Open WebUI
  cannot bind :3000 ("address already in use"). The system stack is what the
  user actually talks to; llama-server (ours) is the backend on :8080.

## Paths (this machine)

README uses fixed base folder `$HOME/llama-ai`.

| What | Path |
|---|---|
| llama.cpp (repo + build) | `$HOME/llama-ai/llama.cpp` |
| Python venv | `$HOME/llama-ai/llama.cpp/venv` |
| models | `$HOME/llama-ai/llama.cpp/models/` |
| service logs | `$HOME/llama-ai/llama.cpp/logs/` |
| admin credentials | `$HOME/llama-ai/owui.env` (created interactively by `setup_credentials.sh`) |
| SearXNG | `$HOME/llama-ai/searxng`, settings in `settings.yml` |
| repo docs | `/tmp/opencode/llama-local-ai` (clone of github.com/zdomjus60/llama-local-ai) |

## Known pitfalls (lessons learned)

1. **Open WebUI requires Python <3.13.** Debian 13 ships only Python 3.13.
   Use Python 3.12 via pyenv: `~/.pyenv/versions/3.12.13/bin/python3 -m venv venv`.
   (`shaderc` is not a Debian package: the binary is `glslc`.)
2. **SearXNG "ModuleNotFoundError: No module named 'searx'"**: the `searx`
   package lives in the repo dir. start_chat.sh MUST launch it with
   `PYTHONPATH="$SEARXNG_DIR"` (fixed; previously it crashed on start).
3. **RX 580 (Polaris) + 8B model = unusably slow** (FP16 1/16 rate, prompt
   processing ~4.6 tok/s, GPU at 100%). Use 4B or smaller models.
4. `--chat-template-kwargs '{"enable_thinking":false}'` is DEPRECATED: use
   `--reasoning off` (warning in the log otherwise).
5. Interrupted downloads = truncated, unusable GGUF. Resume with `curl -L -C -`.
6. The bash tool kills background processes on timeout: use
   `setsid ... & echo started` as the LAST command of the call, no trailing
   `sleep`/`pgrep`, otherwise the tool kills them.
7. `pkill -f '[l]lama-server'` kills itself (pattern matches the running
   shell): use `kill $(pgrep -f '[l]lama-server' | grep -v bash)`.

## Ports

| Port | Service | Scope |
|---|---|---|
| 8080 | llama-server | LAN (0.0.0.0) |
| 3000 | Open WebUI (system stack) | LAN (0.0.0.0) |
| 8888 | SearXNG (system stack) | localhost |
| 11434 | Ollama | not used |

## Possible next steps

- Clean up the double stack (ours in venv vs system /usr/local) or document
  that only llama-server from $HOME/llama-ai is used
- Backup `webui.db` (chats and configured models)
