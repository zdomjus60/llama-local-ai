# Chat IA locale con web search: llama.cpp + Open WebUI + SearXNG

Configurazione completa di un assistente AI privato sulla propria rete locale:

- **llama.cpp** compilato con supporto **GPU (Vulkan)** come motore di inferenza
- **Open WebUI** come interfaccia web (chat, modelli, ricerca web)
- **SearXNG** come meta-motore di ricerca privato per il web search
- Modello principale: **Qwen3 8B Instruct** (quantizzato Q4_K_M)
- Altri modelli configurabili con web search: Qwen2.5 7B, Ornith 9B,
  Gemma 3 1B, Gemma 2 9B, DeepSeek V2 Lite

Tutto gira in locale, nessun dato esce dalla rete di casa.

## Architettura

```
                 browser locale o altro PC in LAN
                            |
                            v
                 +--------------------+
                 |  Open WebUI :3000  |
                 |  (interfaccia chat)|
                 +--------------------+
                      |          |
           /v1 chat   |          | web search
                      v          v
              +-----------+  +-----------+
              | llama.cpp |  | SearXNG   |
              | :8080     |  | :8888     |
              | (GPU)     |  | (motori)  |
              +-----------+  +-----------+
```

Il flusso della ricerca web: la domanda arriva a Open WebUI, che interroga
SearXNG, prende i primi risultati, li inietta nella richiesta al modello e il
modello risponde citando le fonti ([1], [2], ...).

## Hardware e sistema

- CPU/GPU: AMD con GPU integrata **Radeon 680M** (Rembrandt), driver Vulkan **RADV**
- RAM: 16 GB (condivisa tra CPU e GPU integrata)
- SO: Linux (Debian)
- Server raggiungibile in LAN all'indirizzo `192.168.1.XXX` (sostituire con
  l'IP della propria macchina)

## 1. Compilare llama.cpp con GPU (Vulkan)

Per usare la GPU AMD serve il backend Vulkan. Non serve CUDA.

```bash
# prerequisiti
sudo apt install build-essential cmake git \
  libvulkan1 vulkan-tools mesa-vulkan-drivers \
  glslang-tools shaderc

# clonare e compilare
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
cmake -B build -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j$(nproc)
```

Verifica che la GPU venga riconosciuta:

```bash
./build/bin/llama-bench -m models/llama-3.2-3b-instruct-q4_k_m.gguf -p 32 -n 16 -ngl 99 -r 1
```

Deve comparire `AMD Radeon Graphics (RADV REMBRANDT)` e la riga del risultato
deve riportare `Vulkan` come backend.

## 2. Scaricare i modelli

I modelli vanno nella cartella `models/` di llama.cpp. Sul sito
Hugging Face si trovano i file `.gguf`.

Modello principale:

```bash
curl -L -C - -o models/Qwen3-8B-Q4_K_M.gguf \
  https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf
```

Altri modelli a disposizione (sostituiscono Qwen3, da caricare al posto suo):

| Modello | File | Dimensione | Uso |
|---|---|---|---|
| Qwen3 8B Instruct | `Qwen3-8B-Q4_K_M.gguf` | 4,7 GB | **principale** |
| Qwen2.5 7B Instruct | `qwen2.5-7b-instruct-q4_k_m.gguf` | 4,4 GB | riserva |
| Ornith 1.0 9B | `ornith-1.0-9b-Q4_K_M.gguf` | 5,3 GB | riserva |
| Gemma 3 1B | `gemma-3-1b-it-Q4_K_M.gguf` | ~1 GB | risposta veloce, italiano |
| Gemma 2 9B | `gemma-2-9b-it-Q4_K_M.gguf` | ~6 GB | risposta lunga, italiano |
| DeepSeek V2 Lite MoE | `DeepSeek-V2-Lite-Chat.IQ2_S` | ~2,4 GB | riserva, MoE efficiente |
| Llama 3.2 3B | `llama-3.2-3b-instruct-q4_k_m.gguf` | 1,9 GB | test veloci |

I file GGUF si scaricano da Hugging Face (cerco "NOME-MODELLO GGUF").
Per i test rapidi da terminale si puo' usare direttamente
`./build/bin/llama-cli -m models/<file>.gguf -ngl 99 -c 4096`.

Nota: Qwen3 e' un modello "reasoning" (pensa prima di rispondere). Per risposte
dirette e veloci va avviato con l'opzione `--reasoning off`.

Attenzione: un download interrotto produce un file GGUF troncato e
inutilizzabile. Esempio: DeepSeek-R1-Distill-Qwen-7B scaricato a 370 MB invece
di ~4 GB non funziona. Ricontrollare sempre la dimensione del file.

## 3. Installare Open WebUI

Open WebUI gira in un virtual environment Python (stesso venv puo' ospitare
anche SearXNG).

```bash
python3 -m venv venv
venv/bin/pip install --upgrade pip
venv/bin/pip install open-webui
venv/bin/open-webui --version   # verificare l'installazione
```

Al primo avvio viene chiesto di creare l'account amministratore. I dati
(chat, modelli configurati, utenti) stanno nella cartella dati:

```bash
# variabili usate al primo avvio (poi richieste dall'ambiente)
export DATA_DIR=/home/<utente>/openwebui/data
export WEBUI_ADMIN_EMAIL=...
export WEBUI_ADMIN_PASSWORD=...
export WEBUI_ADMIN_NAME=...
venv/bin/open-webui serve --host 0.0.0.0 --port 3000
```

Le credenziali amministratore vanno salvate in un file `.env` fuori dal repo
(vedi `.env.example`).

## 4. Installare e configurare SearXNG

SearXNG interroga piu' motori di ricerca (Google, Bing, DuckDuckGo...) e
restituisce risultati puliti. Installato con lo stesso venv.

```bash
venv/bin/pip install searxng
git clone https://github.com/searxng/searxng.git searxng
# il file di config si genera/avvia cosi':
SEARXNG_SETTINGS_PATH=$PWD/searxng/settings.yml \
  venv/bin/python -m searx.webapp
```

Nel file `settings.yml` la porta di default e' 8888 e il server ascolta solo su
`127.0.0.1` (corretto: deve usarlo solo Open WebUI sulla stessa macchina).
Cambiare `secret_key` prima dell'uso.

## 5. Collegare Open WebUI a llama.cpp

In Open WebUI: **Settings > Connection > OpenAI API** aggiungere il server:

```
URL base: http://localhost:8080/v1
Chiave API: (vuota)
Prefisso id: llama.cpp
```

Oppure, in automatico, eseguendo `start_chat.sh` che fa questo passaggio via API.

## 6. Attivare la ricerca web sul modello

Il trucco che fa funzionare il web search in questo setup:

1. Il modello di chat va creato in Open WebUI con **`function_calling` = `legacy`**
   (cosi' la ricerca la fa Open WebUI e non il modello).
2. Va dichiarata la capability **`web_search: true`** con la feature di default
   `["web_search"]`: solo cosi' il toggle "Web Search" compare e resta attivo
   nella chat.

Esempio di creazione via API (fatto in automatico da `start_chat.sh`, che crea
un modello "Web" per ogni GGUF presente in `models/`):

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

Nota: `base_model_id` e' il **nome file** del GGUF senza cartella (la cartella
`models/` non va inclusa: lo gestisce il router di llama-server).

I modelli "Web" che `start_chat.sh` configura automaticamente (uno per GGUF
trovato):

| id in Open WebUI | modello |
|---|---|
| `qwen3-web` | Qwen3 8B |
| `qwen-web` | Qwen2.5 7B |
| `ornith-web` | Ornith 1.0 9B |
| `gemma3-web` | Gemma 3 1B |
| `gemma2-web` | Gemma 2 9B |
| `deepseek-web` | DeepSeek V2 Lite |

Da quel momento basta selezionare il modello "Web" nella chat e la ricerca
parte da sola quando serve: il modello cerca, legge i risultati e risponde
citando le fonti. L'utente puo' disattivarla col toggle in chat.

### Compattazione automatica del contesto

Per chat lunghe, Open WebUI puo' compattare la cronologia quando supera una
soglia di token:

```
ENABLE_CONTEXT_COMPACTION=true
CONTEXT_COMPACTION_TOKEN_THRESHOLD=12000
CONTEXT_COMPACTION_RETENTION_PERCENTAGE=30
```

## 7. Avvio dei servizi

Il file `start_chat.sh` in questa repo avvia **tutti** i servizi
(SearXNG, llama-server, Open WebUI), configura i modelli con web search e
apre il browser.

llama-server gira come **router multi-modello**: carica i modelli dalla
cartella `models/` al volo e tiene in RAM un solo modello alla volta
(`--models-max 1`,
LRU). I parametri chiave del setup:

```bash
./build/bin/llama-server \
  --models-dir models \   # tutti i GGUF in models/ sono selezionabili da Open WebUI
  --models-max 1 \        # un solo modello in RAM alla volta (LRU)
  -ngl 99 \               # carica il 100% dei layer sulla GPU Vulkan
  -c 16384 \              # contesto 16k token
  -n 2048 \               # max 2048 token per risposta
  -ctk q8_0 -ctv q8_0 \   # KV cache quantizzata (occorre ~1 GiB a 16k)
  --reasoning off \       # disattiva il "thinking" di Qwen3
  --host 0.0.0.0 \        # accessibile anche da altri PC in LAN
  --port 8080
```

KV cache: 32 layer di attenzione con dim 1024 => a 16384 token in q8_0 servono
circa 1 GiB di RAM/VRAM, lo stesso che a 8192 token in f16. Il raddoppio del
contesto non costa memoria.

## 8. Uso da locale e da un altro PC

- Sulla macchina server: `http://localhost:3000`
- Da un altro PC in LAN: `http://<IP-del-server>:3000` (indirizzo IP del server)
- Open WebUI ascolta gia' su `0.0.0.0:3000`, nessun firewall attivo necessario

## 9. Risoluzione problemi

| Sintomo | Causa probabile | Soluzione |
|---|---|---|
| Errore `Connect call failed` verso 11434 | Open WebUI cerca un server Ollama | ignorabile, si usa llama.cpp |
| Il modello non cita fonti / "non so" | web search non attivo | scegliere il modello "Web" e accendere il toggle |
| Risposta troppo lenta | "thinking" di Qwen3 attivo | riavviare con `--reasoning off` |
| Modello non caricabile | GGUF troncato | ricontrollare dimensione e riscaricare con `curl -C -` |
| La UI non mostra il toggle web search | manca `capabilities.web_search` | ricreare il modello come in sezione 6 |
| Un modello non compare in Open WebUI | GGUF assente da `models/` o router non riavviato | copiare il GGUF in `models/` e riavviare llama-server |
| Vram piena / modello non entra | quantizzazione troppo alta o contesto enorme | usare Q4_K_M e `-c 16384`, KV in q8_0 |

## Riferimenti

- llama.cpp: https://github.com/ggml-org/llama.cpp
- Open WebUI: https://github.com/open-webui/open-webui
- SearXNG: https://github.com/searxng/searxng
- Qwen3-8B GGUF: https://huggingface.co/Qwen/Qwen3-8B-GGUF
