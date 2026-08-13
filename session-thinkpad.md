# Sessione - Configurazione agente su ThinkPad T480

## Contesto

Conversazione avvenuta su questo PC (quello con llama.cpp + Open WebUI).
Trasferita sul ThinkPad per continuare il lavoro da li'.

## Configurazione attuale (questo PC)

- **llama.cpp** compilato in `build/`, con llama-server.
- Modello attivo: `models/Qwen3-8B-Q4_K_M.gguf` su porta 8080.
- **Open WebUI** su porta 3000, con ricerca web via **SearXNG** (porta 8888).
- Script di avvio presenti: `start_chat.sh`, `start_all.sh`, `start_web.sh`, `start_webui.sh`.
- RAM 16 GB totali (8 preassegnati alla VRAM GPU), `free` mostra 7.5 GiB + swap.
- Llama-server supporta gia' il function calling (testato: il modello emette `tool_calls` correttamente).
- L'agente NON carica un secondo modello: usa llama-server via HTTP.
  Costo marginale: Open WebUI tools = zero; CLI agent = 100-300 MB.

## Obiettivo

Agente capace di operare localmente su file/directory, usando il modello locale.
Caso d'uso principale: **progettazione di applicazioni Flutter, costrutti complessi**.
Il progetto Flutter sta sul ThinkPad.

## Decisioni prese

- Framework scelto: **aider** (non openclaw; openclaw e' escluso da llama.cpp per
  contributi autonomi, e aider e' piu' adatto all'editing di codice).
- Non si modifica opencode (l'utente lo usa volentieri con big-pickle).
- Il modello per aider gira **sul ThinkPad**, non su questo PC
  (l'8B attuale e' troppo debole per Flutter complesso).

## Specifiche ThinkPad T480

- RAM: **32 GB DDR4**.
- GPU: **Sapphire AMD RX 580 eGPU** via Thunderbolt 3, ~8 GB VRAM,
  **funziona a intermittenza**.
- Strategia: **CPU-first**. LLM MoE cosi' va comunque bene su CPU.
  Quando la eGPU risponde, si offloda con `-ngl`, altrimenti si parte a `-ngl 0`.

## Modello consigliato

- **Qwen3-Coder-30B-A3B-Instruct**, Q4_K_M (~19 GB).
  - MoE con ~3B parametri attivi: veloce anche su CPU del T480 (~8-12 tok/s).
  - Sta comodo nei 32 GB di RAM.
  - Con eGPU attiva: offload parziale, guadagno 2-3x.
  - E' la famiglia Coder, la migliore per aider.

## Azioni da compiere sul ThinkPad

1. Installare llama.cpp (o copiare la build x86_64 da questo PC).
2. Scaricare il GGUF: `models/Qwen3-Coder-30B-A3B-Q4_K_M.gguf`.
3. Creare `start_t480.sh` con probe GPU:
   - `lspci | grep -qi "RX 580"` -> `-ngl 99`, altrimenti `-ngl 0`.
   - Opzione ROCm per RX 580 (Polaris): `HSA_OVERRIDE_GFX_VERSION=11.0.0`
     se si usa il driver open di ROCm.
   - `-c 16384 -n 2048 --port 8080`.
4. `pip install aider-chat`.
5. Comando aider:
   ```
   aider --openai-api-base http://localhost:8080/v1 \
         --openai-api-key local \
         --model openai/gpt-4o-mini \
         --edit-format whole
   ```
   (nome modello = alias, aider parla comunque col server locale;
   `--edit-format whole` consigliato per modelli locali).
6. Creare AGENTS.md nel progetto Flutter con le convenzioni del progetto.

## Note

- Su llama-server usare sempre il template tool-aware (gia' presente nel Qwen3).
- `-ctk q4_0` degrada il tool calling: non usare quantizzazioni KV estreme.
- Aider sul T480: preferire `--edit-format whole`.
