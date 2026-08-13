# Local AI chat with web search

Private AI assistant on your local network: **llama.cpp** (GPU/Vulkan) +
**Open WebUI** (chat interface) + **SearXNG** (private web search).

## Requirements

- A GPU with Vulkan support (AMD, Intel, NVIDIA all work)
- Linux (Debian 13 tested)
- Enough RAM for the model (Qwen3 8B needs ~7 GB)

## The venv rule (read this first)

There is ONE Python environment (the "venv"). It lives at
`$HOME/llama-ai/llama.cpp/venv` and it is created in step 5.

**You never have to "activate" it** — you never run
`source venv/bin/activate`. Every command that uses it points directly at it
with a full path. If a command does not contain `venv/`, it does not use the
venv.

---

## How to install

Follow the steps **in order**. Every step tells you which folder you are in
and whether the venv is involved. At the end everything lives in a single
folder: `$HOME/llama-ai/`.

---

### Step 1 - Create the folders and download llama.cpp

Folder: **your home folder** (the commands move you automatically).
Venv: **not involved**.

```bash
mkdir -p "$HOME/llama-ai"
cd "$HOME/llama-ai"
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
```

Now you are in `$HOME/llama-ai/llama.cpp`.

---

### Step 2 - Install the system packages

Folder: **any** (system-wide).
Venv: **not involved**.

```bash
sudo apt install build-essential cmake git \
  libvulkan1 libvulkan-dev vulkan-tools mesa-vulkan-drivers \
  glslang-tools glslc spirv-headers
```

---

### Step 3 - Build llama.cpp

Folder: **`$HOME/llama-ai/llama.cpp`** (from step 1).
Venv: **not involved**.

```bash
cmake -B build -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j$(nproc)
```

Check that your GPU is seen:

```bash
vulkaninfo --summary | grep deviceName
```

You should see your GPU name (for example `AMD Radeon ... (RADV)`).

---

### Step 4 - Download the main model

Folder: **`$HOME/llama-ai/llama.cpp`** (from step 3).
Venv: **not involved**.

```bash
mkdir -p models
curl -L -C - -o models/Qwen3-8B-Q4_K_M.gguf \
  https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf
```

Wait until the download finishes (about 4.7 GB).

---

### Step 5 - Create the Python environment and install Open WebUI

Folder: **`$HOME/llama-ai/llama.cpp`** (from step 4).
Venv: **created here**. From now on it is `$HOME/llama-ai/llama.cpp/venv`.

Debian 13 ships Python 3.13, but Open WebUI needs Python 3.12. These commands
install Python 3.12 once, then create the venv **with it**:

```bash
# 1) packages needed to build Python 3.12 (system-wide)
sudo apt install build-essential libssl-dev zlib1g-dev libbz2-dev \
  libreadline-dev libsqlite3-dev libffi-dev liblzma-dev

# 2) install pyenv (once per user) - system tool, not the venv
curl -fsSL https://pyenv.run | bash

# 3) install Python 3.12 (takes a few minutes; skip if already installed)
~/.pyenv/bin/pyenv install 3.12.13

# 4) create the venv and install Open WebUI inside it
~/.pyenv/versions/3.12.13/bin/python3 -m venv venv
venv/bin/pip install --upgrade pip
venv/bin/pip install open-webui
```

The last three commands are the only ones that touch the venv. The path
`venv/bin/pip` is relative: it works because you are inside `llama.cpp`, where
the `venv` folder sits.

---

### Step 6 - Install SearXNG

Folder: **`$HOME/llama-ai`** (note: OUTSIDE the `llama.cpp` folder; this is
the only step that leaves it).
Venv: **used**, but with the FULL path — you are not in `llama.cpp` anymore,
so the relative `venv/bin/pip` would not work here.

```bash
cd "$HOME/llama-ai"
git clone https://github.com/searxng/searxng.git
cd searxng
"$HOME/llama-ai/llama.cpp/venv/bin/pip" install -r requirements.txt
```

Create the SearXNG configuration file (the secret key is generated for you;
this uses the system Python, not the venv):

```bash
SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
cat > settings.yml <<EOF
use_default_settings: true

server:
  secret_key: "$SECRET"
  bind_address: "127.0.0.1"
  port: 8888
  limiter: false
  public_instance: false

search:
  formats:
    - html
    - json
EOF
```

---

### Step 7 - Create the admin credentials

Folder: **any** (the file is created at the right path).
Venv: **not involved**.

```bash
mkdir -p "$HOME/llama-ai"
cat > "$HOME/llama-ai/owui.env" <<EOF
WEBUI_ADMIN_EMAIL=you@example.com
WEBUI_ADMIN_PASSWORD=change-this-password
WEBUI_ADMIN_NAME=Admin
EOF
```

Replace the email and password with your own.

---

### Step 8 - Start everything

Folder: **`$HOME/llama-ai/llama.cpp`** (from step 5).
Venv: **not involved** — the script finds it by itself.

```bash
cd "$HOME/llama-ai/llama.cpp"
curl -L -o start_chat.sh \
  https://raw.githubusercontent.com/zdomjus60/llama-local-ai/main/start_chat.sh
chmod +x start_chat.sh
./start_chat.sh
```

The script starts SearXNG, llama-server and Open WebUI, configures the web
search and opens your browser.

---

## Use it

- On this PC: `http://localhost:3000`
- From another PC on the LAN: `http://<server-IP>:3000`

In the chat, pick the model **Qwen3 8B (Web)**.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `pip install open-webui` fails "No matching distribution" | Python 3.13 is being used. Recreate the venv with Python 3.12 (step 5, point 4). |
| `venv/bin/pip` not found | You are not in the `llama.cpp` folder. Run `cd "$HOME/llama-ai/llama.cpp"` and check the `venv` folder exists. |
| Web search does nothing | Check `$HOME/llama-ai/searxng/settings.yml` still has `- json` under `search.formats`. |
| Model does not answer / cites nothing | Select a "Web" model in the chat and turn the search toggle on. |
| Download stopped halfway | Run the same `curl -L -C -` command again to resume. |

## References

- llama.cpp: https://github.com/ggml-org/llama.cpp
- Open WebUI: https://github.com/open-webui/open-webui
- SearXNG: https://github.com/searxng/searxng
- Qwen3-8B GGUF: https://huggingface.co/Qwen/Qwen3-8B-GGUF
