./build/bin/llama-server \
  -m models/Qwen3-8B-Q4_K_M.gguf \
  -ngl 99 \
  -c 16384 \
  -n 2048 \
  -ctk q8_0 \
  -ctv q8_0 \
  --reasoning off \
  --host 0.0.0.0 \
  --port 8080
