# Local AI chat with web search: llama.cpp + Open WebUI + SearXNG

Complete setup of a private AI assistant on your own local network:

- **llama.cpp** compiled with **GPU (Vulkan)** support as the inference engine
- **Open WebUI** as the web interface (chat, models, web search)
- **SearXNG** as a private meta-search engine for web search
- Main model: **Qwen3 8B Instruct** (Q4_K_M quantized)
- Other models that can be configured with web search: Qwen2.5 7B, Ornith 9B,
  Gemma 3 1B, Gemma 2 9B, DeepSeek V2 Lite

Everything runs locally. Web searches are proxied through your own SearXNG
instance, so your queries are not sent directly to Google/Bing with your IP.

## Architecture

```
                 local browser or another PC on the LAN
                            |
                            v
                 +--------------------+
                 |  Open WebUI :3000  |
                 |  (chat interface)  |
                 +--------------------+
                      |          |
           /v1 chat   |          | web search
                      v          v
              +-----------+  +-----------+
              | llama.cpp |  | SearXNG   |
              | :8080     |  | :8888     |
              | (GPU)     |  | (engines) |
              +-----------+  +-----------+
```

How web search works: your question reaches Open WebUI, which asks SearXNG,
takes the top results, injects them into the request to the model, and the
model answers citing its sources ([1], [2], ...).

## Hardware and system

- CPU/GPU: AMD with integrated **Radeon 680M** (Rembrandt), Vulkan **RADV** drivers
- RAM: 16 GB (shared between CPU and integrated GPU)
- OS: Linux (Debian)
- Server reachable on the LAN at `192.168.1.XXX` (replace with your machine's IP)

## 1. Build llama.cpp with GPU (Vulkan)

To use an AMD GPU you need the Vulkan backend. CUDA is not required.

```bash
# prerequisites
sudo apt install build-essential cmake git \
  libvulkan1 libvulkan-dev vulkan-tools mesa-vulkan-drivers \
  glslang-tools glslc spirv-headers

# clone and build
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
cmake -B build -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j$(nproc)
```

Verify the GPU is detected:

```bash
./build/bin/llama-bench -m models/llama-3.2-3b-instruct-q4_k_m.gguf -p 32 -n 16 -ngl 99 -r 1
```

You should see `AMD Radeon Graphics (RADV REMBRANDT)` and the result row must
report `Vulkan` as the backend.

Note: this benchmark needs the Llama 3.2 3B file first. Download it with:

```bash
curl -L -C - -o models/llama-3.2-3b-instruct-q4_k_m.gguf \
  https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf
```

## 2. Download the models

Models go into the `models/` folder of llama.cpp. GGUF files are hosted on
Hugging Face.

Main model:

```bash
curl -L -C - -o models/Qwen3-8B-Q4_K_M.gguf \
  https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf
```

Other available models (to load in addition to Qwen3):

| Model | File | Size | Use |
|---|---|---|---|
| Qwen3 8B Instruct | `Qwen3-8B-Q4_K_M.gguf` | 4.7 GB | **main** |
| Qwen2.5 7B Instruct | `qwen2.5-7b-instruct-q4_k_m.gguf` | 4.4 GB | backup |
| Ornith 1.0 9B | `ornith-1.0-9b-Q4_K_M.gguf` | 5.3 GB | backup |
| Gemma 3 1B | `gemma-3-1b-it-Q4_K_M.gguf` | ~1 GB | fast answers, Italian |
| Gemma 2 9B | `gemma-2-9b-it-Q4_K_M.gguf` | ~6 GB | long answers, Italian |
| DeepSeek V2 Lite MoE | `DeepSeek-V2-Lite-Chat.IQ2_S.gguf` | ~6 GB | backup, efficient MoE |
| Llama 3.2 3B | `llama-3.2-3b-instruct-q4_k_m.gguf` | 1.9 GB | quick tests |

Download GGUF files from Hugging Face (search "MODEL-NAME GGUF"). For quick
terminal tests you can run:
`./build/bin/llama-cli -m models/<file>.gguf -ngl 99 -c 4096`.

Note: Qwen3 is a "reasoning" model (it thinks before answering). For direct,
fast answers run it with `--reasoning off`.

Warning: an interrupted download produces a truncated, unusable GGUF. Always
re-check the file size. Example: DeepSeek-R1-Distill-Qwen-7B downloaded at
370 MB instead of ~4 GB does not work.

## 3. Install Open WebUI

Open WebUI runs in a Python virtual environment (the same venv can also host
SearXNG).

**Debian 13 ships only Python 3.13, but Open WebUI requires Python 3.11/3.12.**
On a stock Debian 13 `pip install open-webui` fails with
`ERROR: Could not find a version that satisfies the requirement open-webui`,
because every release requires `<3.13`. Install Python 3.12 with pyenv first:

```bash
# Python 3.12 build dependencies
sudo apt install build-essential libssl-dev zlib1g-dev libbz2-dev \
  libreadline-dev libsqlite3-dev libffi-dev liblzma-dev

# install pyenv and Python 3.12 (takes a few minutes, source build)
curl -fsSL https://pyenv.run | bash
~/.pyenv/bin/pyenv install 3.12.13

# create the venv with Python 3.12 (NOT the system python3 = 3.13)
~/.pyenv/versions/3.12.13/bin/python -m venv venv
venv/bin/pip install --upgrade pip
venv/bin/pip install open-webui
venv/bin/python -m pip show open-webui | grep ^Version   # verify the install
```

Note: `python3 -m venv venv` would use the system Python 3.13 and Open WebUI
cannot be installed there. Use the explicit pyenv path above.

On first start you are asked to create the administrator account. Data (chat,
configured models, users) lives in the data folder:

```bash
# variables used on first start (then required from the environment)
export DATA_DIR=/home/<user>/openwebui/data
export WEBUI_ADMIN_EMAIL=...
export WEBUI_ADMIN_PASSWORD=...
export WEBUI_ADMIN_NAME=...
venv/bin/open-webui serve --host 0.0.0.0 --port 3000
```

If `WEBUI_ADMIN_*` variables are set, Open WebUI creates the admin account
automatically on first start; otherwise it asks interactively.

## 4. Install and configure SearXNG

SearXNG queries several search engines (Google, Bing, DuckDuckGo, ...) and
returns clean results. It is not installed as a pip package: it runs from a git
clone, using the Python interpreter of the same venv.

```bash
git clone https://github.com/searxng/searxng.git searxng
venv/bin/pip install -r searxng/requirements.txt
```

Create `searxng/settings.yml`. The minimal working configuration is:

```yaml
use_default_settings: true

server:
  secret_key: "REPLACE-WITH-A-RANDOM-STRING"
  bind_address: "127.0.0.1"
  port: 8888
  limiter: false
  public_instance: false

search:
  formats:
    - html
    - json
```

Two details are critical:

- `server.port: 8888` and `server.bind_address: "127.0.0.1"`: only Open WebUI on
  the same machine must reach it.
- `search.formats` must include **`json`**: Open WebUI requests
  `/search?format=json`, and without it the web search silently fails.

Start SearXNG from inside the `searxng/` folder (the module is imported from
the current directory):

```bash
cd searxng
SEARXNG_SETTINGS_PATH=$PWD/settings.yml \
  venv/bin/python -m searx.webapp
```

Generate the `secret_key` with:

```bash
python3 -c "import secrets; print(secrets.token_hex(32))"
```

## 5. Connect Open WebUI to llama.cpp

In Open WebUI: **Settings > Connection > OpenAI API**, add the server:

```
Base URL: http://localhost:8080/v1
API key: (empty)
ID prefix: llama.cpp
```

Or automatically, by running `start_chat.sh`, which does this step via API.

## 6. Enable web search on a model

The trick that makes web search work in this setup:

1. The chat model must be created in Open WebUI with **`function_calling` = `legacy`**
   (so the search is done by Open WebUI, not by the model).
2. The **`web_search: true`** capability with the default feature
   `["web_search"]` must be declared: only then the "Web Search" toggle appears
   and stays active in the chat.

API creation example (done automatically by `start_chat.sh`, which creates a
"Web" model for every GGUF found in `models/`):

```bash
curl -X POST http://localhost:3000/api/v1/models/create -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{
    "id": "qwen3-web",
    "base_model_id": "Qwen3-8B-Q4_K_M",
    "name": "Qwen3 8B (Web)",
    "params": {"function_calling": "legacy"},
    "meta": {
      "defaultFeatureIds": ["web_search"],
      "capabilities": {"web_search": true}
    }
  }'
```

Note: `base_model_id` is the GGUF **file name without the folder** (do not
include `models/`: the llama-server router handles it).

The "Web" models configured automatically by `start_chat.sh` (one per GGUF
found):

| id in Open WebUI | model |
|---|---|
| `qwen3-web` | Qwen3 8B |
| `qwen-web` | Qwen2.5 7B |
| `ornith-web` | Ornith 1.0 9B |
| `gemma3-web` | Gemma 3 1B |
| `gemma2-web` | Gemma 2 9B |
| `deepseek-web` | DeepSeek V2 Lite |

From then on, just select the "Web" model in the chat and the search starts by
itself when needed: the model searches, reads the results and answers citing
the sources. The user can turn it off with the toggle in the chat.

### Automatic context compaction

For long chats, Open WebUI can compact the history when it exceeds a token
threshold:

```
ENABLE_CONTEXT_COMPACTION=true
CONTEXT_COMPACTION_TOKEN_THRESHOLD=12000
CONTEXT_COMPACTION_RETENTION_PERCENTAGE=30
```

## 7. Start the services

The `start_chat.sh` file in this repo starts **all** services (SearXNG,
llama-server, Open WebUI), configures the models with web search and opens the
browser.

llama-server runs as a **multi-model router**: it loads models from the
`models/` folder on demand and keeps only one model in RAM at a time
(`--models-max 1`, LRU). Key parameters:

```bash
./build/bin/llama-server \
  --models-dir models \   # all GGUF in models/ become selectable in Open WebUI
  --models-max 1 \        # one model in RAM at a time (LRU)
  -ngl 99 \               # load 100% of layers on the Vulkan GPU
  -c 16384 \              # 16k token context
  -n 2048 \               # max 2048 tokens per answer
  -ctk q8_0 -ctv q8_0 \   # quantized KV cache (~1 GiB at 16k)
  --reasoning off \       # disable Qwen3 "thinking"
  --host 0.0.0.0 \        # reachable from other PCs on the LAN
  --port 8080
```

KV cache: 32 attention layers with dim 1024 => at 16384 tokens in q8_0 about
1 GiB of RAM/VRAM is needed, the same as 8192 tokens in f16. Doubling the
context costs no memory.

### About the paths in `start_chat.sh`

`start_chat.sh` must be placed **inside the llama.cpp folder** (it uses
`./build/bin/llama-server`, `./venv`, `models/`). It assumes this layout:

| Path | Used for |
|---|---|
| `$HOME/Scrivania/owui.env` | admin credentials (see `.env.example`) |
| `$HOME/Scrivania/searxng` | SearXNG git clone with `settings.yml` |
| `$HOME/Scrivania/openwebui/data` | Open WebUI data (webui.db) |

The `owui.env` file (outside the repo, never committed) must contain:

```bash
WEBUI_ADMIN_EMAIL=you@example.com
WEBUI_ADMIN_PASSWORD=your-password
WEBUI_ADMIN_NAME=YourName
```

The `/v1` connection and the "Web" models are created automatically via API on
every run (idempotent).

## 8. Use it locally or from another PC

- On the server machine: `http://localhost:3000`
- From another PC on the LAN: `http://<server-IP>:3000`
- Open WebUI already listens on `0.0.0.0:3000`, no firewall needed

## 9. Troubleshooting

| Symptom | Probable cause | Solution |
|---|---|---|
| `Connect call failed` to 11434 | Open WebUI looks for an Ollama server | ignore, llama.cpp is used |
| Model does not cite sources / "I don't know" | web search not enabled | pick a "Web" model and turn the toggle on |
| Answer too slow | Qwen3 "thinking" enabled | restart with `--reasoning off` |
| Model cannot be loaded | truncated GGUF | check size and re-download with `curl -C -` |
| UI does not show the web search toggle | missing `capabilities.web_search` | recreate the model as in section 6 |
| A model does not appear in Open WebUI | GGUF missing from `models/` or router not restarted | copy the GGUF into `models/` and restart llama-server |
| Web search always fails | `settings.yml` missing `formats: json` | add `- json` under `search.formats` and restart SearXNG |
| `pip install open-webui` fails: "No matching distribution found" | system Python is 3.13 (Debian 13 default), Open WebUI needs `<3.13` | install Python 3.12 with pyenv and recreate the venv (section 3) |
| VRAM full / model does not fit | quant too high or huge context | use Q4_K_M and `-c 16384`, KV in q8_0 |

## References

- llama.cpp: https://github.com/ggml-org/llama.cpp
- Open WebUI: https://github.com/open-webui/open-webui
- SearXNG: https://github.com/searxng/searxng
- Qwen3-8B GGUF: https://huggingface.co/Qwen/Qwen3-8B-GGUF
