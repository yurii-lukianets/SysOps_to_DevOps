# LLM API — Test Results

## Environment
- **Endpoint:** https://llm.ai-devops.pp.ua
- **Model:** Qwen3-35B (Qwen3.6-35B-A3B-MXFP4_MOE.gguf)
- **Hardware:** NVIDIA RTX 3050 8GB VRAM, Intel i5-12600K
- **Runtime:** llama.cpp (CUDA, MXFP4 quantization)
- **Tested:** 2026-05-23

## Test Suite Results

| # | Test | Result | Notes |
|---|------|--------|-------|
| 1 | Health endpoint (public) | ✅ PASS | No auth required |
| 2 | Auth required without key | ✅ PASS | Returns 403 |
| 3 | Auth with valid key | ✅ PASS | Returns choices |
| 4 | Models endpoint | ✅ PASS | Returns Qwen3 model |
| 5 | LLM basic reasoning | ✅ PASS | Correct response |
| 6 | OpenAI-compatible endpoint | ✅ PASS | /v1/chat/completions |

**Results: 6/6 passed**

## Performance (RTX 3050, 35B model)
- Prompt processing: ~6-30 tokens/sec
- Generation: ~9-21 tokens/sec
- Context window: 32768 tokens

## API Usage

### Health check (public)
```bash
curl https://llm.ai-devops.pp.ua/health
# {"status":"ok","llm_backend":"...","model":"Qwen3-35B"}
```

### Chat (requires API key)
```bash
curl -X POST https://llm.ai-devops.pp.ua/v1/chat \
  -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_KEY" \
  -d '{"message": "What is GitOps?", "max_tokens": 100}'
```

### OpenAI-compatible (requires API key)
```bash
curl -X POST https://llm.ai-devops.pp.ua/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_KEY" \
  -d '{
    "model": "qwen3",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 100
  }'
```

### Run full test suite
```bash
git clone https://github.com/yurii-lukianets/SysOps_to_DevOps
cd SysOps_to_DevOps
export API_KEY=your-key
bash llm-api/tests/test_api.sh https://llm.ai-devops.pp.ua
```

## Security
- `/health` — public (no auth)
- `/v1/*` — requires `X-API-Key` header
- Invalid/missing key → `403 Forbidden`
- TLS 1.3 (Let's Encrypt, auto-renewed)

## Stack
