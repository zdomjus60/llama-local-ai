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

## Requirements

- **GPU with Vulkan support** (AMD RADV, Intel ANV, NVIDIA): required for the
  Vulkan backend of llama.cpp. Works with discrete and integrated GPUs.
- **RAM**: enough to hold the model plus the KV cache. Example: Qwen3 8B
  Q4_K_M needs roughly 7 GB; a 1-3B model runs on 2-4 GB.
- **OS**: Linux (Debian 13 tested; Ubuntu works the same).
- **LAN**: the server is reachable from other PCs at
  `http://<server-IP>:3000` (use your machine's IP, the examples use a
  placeholder).

## Where everything lives

All the work happens in a single base folder, `$BASE_DIR`. Set it once in your
terminal and reuse it for every command below:

```bash
export BASE_DIR=$HOME/Scrivania    # example; Scrivania = Italian "Desktop"
```

It can be any path you like (`$HOME/llama-ai`, `$HOME/Desktop`, ...). Two
folders, with a fixed rule:

- **Inside `$BASE_DIR/llama.cpp/`** -> llama.cpp source, `build/`, `models/`,
  `venv/`, `logs/`, `start_chat.sh`
- **Outside it, directly in `$BASE_DIR/`** -> `searxng/`, `openwebui/data/`,
  `owui.env`

```
$BASE_DIR/
├── owui.env              # admin credentials (never committed, see .env.example)
├── llama.cpp/            # everything created in install steps 1-3
│   ├── build/            # compiled llama.cpp binaries (llama-server, ...)
│   ├── models/           # GGUF model files
│   ├── venv/             # Python virtual environment (Open WebUI + SearXNG)
│   ├── logs/             # service logs
│   └── start_chat.sh     # start-all script (copy from this repo)
├── searxng/              # created in step 4
└── openwebui/data/       # Open WebUI data (webui.db)
```

**One venv for everything.** There is a single virtual environment at
`$BASE_DIR/llama.cpp/venv`, created in step 3 and shared by Open WebUI and
SearXNG. Always call it by full path
(`$BASE_DIR/llama.cpp/venv/bin/...`). Never use `sudo pip` system-wide: the
system Python is 3.13 and cannot install Open WebUI.

`start_chat.sh` is the start-all script provided in this repo; you copy it
into `$BASE_DIR/llama.cpp/` in install step 6. It reads `$BASE_DIR` too
(default: `$HOME/Scrivania`), so it always finds `owui.env`, `searxng/` and
`openwebui/data` where you put them.

Each install step below states where you work. Follow them in order.

---

## Install step 1 - Build llama.cpp with Vulkan

**Work in:** `$BASE_DIR/` (you do not need to create the folder, the
clone does it).

To use an AMD GPU you need the Vulkan backend. CUDA is not required.

```bash
# prerequisites (system-wide, run anywhere)
sudo apt install build-essential cmake git \
  libvulkan1 libvulkan-dev vulkan-tools mesa-vulkan-drivers \
  glslang-tools glslc spirv-headers

# clone and build
cd "$BASE_DIR"
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
cmake -B build -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j$(nproc)
```

Verify the GPU is detected:

```bash
./build/bin/llama-bench -m models/llama-3.2-3b-instruct-q4_k_m.gguf -p 32 -n 16 -ngl 99 -r 1
```

You should see your GPU name (for example `AMD Radeon Graphics (RADV)`) and the
result row must report `Vulkan` as the backend.

Note: this benchmark needs the Llama 3.2 3B file first. Download it with:

```bash
curl -L -C - -o models/llama-3.2-3b-instruct-q4_k_m.gguf \
  https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf
```

## Install step 2 - Download the models

**Work in:** `$BASE_DIR/llama.cpp/` (from step 1). Models go into the
`models/` folder.

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

Notes:

- Qwen3 is a "reasoning" model (it thinks before answering). For direct, fast
  answers run it with `--reasoning off`.
- An interrupted download produces a truncated, unusable GGUF. Always re-check
  the file size. Example: DeepSeek-R1-Distill-Qwen-7B downloaded at 370 MB
  instead of ~4 GB does not work.

## Install step 3 - Create the venv and install Open WebUI

**Work in:** `$BASE_DIR/llama.cpp/` (from step 2). The venv is created
here as `./venv` and reused by everything else.

**Debian 13 ships only Python 3.13, but Open WebUI requires Python 3.11/3.12.**
On a stock Debian 13 `pip install open-webui` fails with
`ERROR: Could not find a version that satisfies the requirement open-webui`,
because every release requires `<3.13`. Install Python 3.12 with pyenv first:

```bash
# Python 3.12 build dependencies (system-wide, run anywhere)
sudo apt install build-essential libssl-dev zlib1g-dev libbz2-dev \
  libreadline-dev libsqlite3-dev libffi-dev liblzma-dev

# install pyenv and Python 3.12 (takes a few minutes, source build)
curl -fsSL https://pyenv.run | bash
~/.pyenv/bin/pyenv install 3.12.13

# create the venv with Python 3.12 (NOT the system python3 = 3.13)
~/.pyenv/versions/3.12.13/bin/python3 -m venv venv
venv/bin/pip install --upgrade pip
venv/bin/pip install open-webui
venv/bin/python3 -m pip show open-webui | grep ^Version   # verify the install
```

Notes:

- `python3 -m venv venv` would use the system Python 3.13 and Open WebUI
  cannot be installed there. Use the explicit pyenv path above.
- The venv is **mandatory**: do not install Open WebUI with system pip.

Manual first start (optional: you normally do this in step 6 with the start
script, which uses the same data folder `$BASE_DIR/openwebui/data`). You are
asked to create the administrator account, or it is created automatically from
the `WEBUI_ADMIN_*` variables:

```bash
export DATA_DIR=$BASE_DIR/openwebui/data
export WEBUI_ADMIN_EMAIL=you@example.com
export WEBUI_ADMIN_PASSWORD=your-password
export WEBUI_ADMIN_NAME=YourName
venv/bin/open-webui serve --host 0.0.0.0 --port 3000
```

## Install step 4 - Install and configure SearXNG

**Work in:** `$BASE_DIR/` (this is the one step OUTSIDE `llama.cpp/`;
do not clone SearXNG inside it).

SearXNG queries several search engines (Google, Bing, DuckDuckGo, ...) and
returns clean results. It is not installed as a pip package: it runs from a git
clone, using the Python interpreter of the **same venv** from step 3 (no
second venv, no system pip). `start_chat.sh` expects it at
`$BASE_DIR/searxng`:

```bash
# run from ANY directory (paths are absolute)
git clone https://github.com/searxng/searxng.git "$BASE_DIR/searxng"
$BASE_DIR/llama.cpp/venv/bin/pip install -r "$BASE_DIR/searxng/requirements.txt"
```

Create `$BASE_DIR/searxng/settings.yml`. The minimal working
configuration is:

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

Generate the `secret_key` (use the system python3, it is only a one-liner):

```bash
python3 -c "import secrets; print(secrets.token_hex(32))"
```

Start SearXNG manually, from inside the `searxng/` folder (the module is
imported from the current directory). Normally `start_chat.sh` does this for
you:

```bash
cd "$BASE_DIR/searxng"
SEARXNG_SETTINGS_PATH=$PWD/settings.yml \
  "$BASE_DIR/llama.cpp/venv/bin/python3" -m searx.webapp
```

## Install step 5 - Create the admin credentials

**File:** `$BASE_DIR/owui.env` (outside the repo, never committed).
`start_chat.sh` fails if this file is missing. Copy `.env.example` and fill it
in:

```bash
WEBUI_ADMIN_EMAIL=you@example.com
WEBUI_ADMIN_PASSWORD=your-password
WEBUI_ADMIN_NAME=YourName
```

## Install step 6 - Start everything

**Work in:** `$BASE_DIR/llama.cpp/` (the script uses `./build`,
`./venv`, `models/`). Copy `start_chat.sh` from this repo into that folder and
run it:

```bash
cd "$BASE_DIR/llama.cpp"
./start_chat.sh
```

The script starts SearXNG, llama-server and Open WebUI, waits until they are
ready, then automatically:

1. connects Open WebUI to llama.cpp (`http://localhost:8080/v1`);
2. creates the "Web" models (one per GGUF in `models/`, web search enabled);
3. opens the browser.

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

KV cache: its size depends on the model architecture and the context length.
Quantizing it (`-ctk q8_0 -ctv q8_0`) roughly halves the memory cost compared
to f16; halving the context (`-c 8192`) halves it again. Start with
`-c 16384` and lower it if your GPU/RAM is tight.

## Use it locally or from another PC

- On the server machine: `http://localhost:3000`
- From another PC on the LAN: `http://<server-IP>:3000`
- Open WebUI already listens on `0.0.0.0:3000`, no firewall needed

Pick a "Web" model in the chat (e.g. `Qwen3 8B (Web)`): web search is enabled
by default, the model searches on its own and cites the sources. The user can
turn it off with the toggle in the chat.

## How the "Web" models work (reference)

The trick that makes web search work in this setup:

1. The chat model must be created in Open WebUI with **`function_calling` = `legacy`**
   (so the search is done by Open WebUI, not by the model).
2. The **`web_search: true`** capability with the default feature
   `["web_search"]` must be declared: only then the "Web Search" toggle appears
   and stays active in the chat.

`start_chat.sh` does this automatically for every GGUF found in `models/`. The
models created are:

| id in Open WebUI | model |
|---|---|
| `qwen3-web` | Qwen3 8B |
| `qwen-web` | Qwen2.5 7B |
| `ornith-web` | Ornith 1.0 9B |
| `gemma3-web` | Gemma 3 1B |
| `gemma2-web` | Gemma 2 9B |
| `deepseek-web` | DeepSeek V2 Lite |

Manual API creation example (what `start_chat.sh` does):

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

To connect Open WebUI to llama.cpp manually instead: **Settings > Connection >
OpenAI API**, add `http://localhost:8080/v1`, empty API key, ID prefix
`llama.cpp`.

### Automatic context compaction

For long chats, Open WebUI can compact the history when it exceeds a token
threshold:

```
ENABLE_CONTEXT_COMPACTION=true
CONTEXT_COMPACTION_TOKEN_THRESHOLD=12000
CONTEXT_COMPACTION_RETENTION_PERCENTAGE=30
```

## Troubleshooting

| Symptom | Probable cause | Solution |
|---|---|---|
| `Connect call failed` to 11434 | Open WebUI looks for an Ollama server | ignore, llama.cpp is used |
| Model does not cite sources / "I don't know" | web search not enabled | pick a "Web" model and turn the toggle on |
| Answer too slow | Qwen3 "thinking" enabled | restart with `--reasoning off` |
| Model cannot be loaded | truncated GGUF | check size and re-download with `curl -C -` |
| UI does not show the web search toggle | missing `capabilities.web_search` | recreate the model (see "Web" models reference) |
| A model does not appear in Open WebUI | GGUF missing from `models/` or router not restarted | copy the GGUF into `models/` and restart llama-server |
| Web search always fails | `settings.yml` missing `formats: json` | add `- json` under `search.formats` and restart SearXNG |
| `pip install open-webui` fails: "No matching distribution found" | system Python is 3.13 (Debian 13 default), Open WebUI needs `<3.13` | install Python 3.12 with pyenv and recreate the venv (install step 3) |
| VRAM full / model does not fit | quant too high or huge context | use a Q4_K_M quant, a smaller `-c`, KV in q8_0 |

## References

- llama.cpp: https://github.com/ggml-org/llama.cpp
- Open WebUI: https://github.com/open-webui/open-webui
- SearXNG: https://github.com/searxng/searxng
- Qwen3-8B GGUF: https://huggingface.co/Qwen/Qwen3-8B-GGUF
