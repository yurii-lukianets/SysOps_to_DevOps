from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import httpx
import os

app = FastAPI(
    title="Self-hosted LLM API",
    description="Proxy to local Qwen3 via llama.cpp",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

LLAMA_URL = os.getenv("LLAMA_SERVER_URL", "http://192.168.100.15:8080")

class ChatRequest(BaseModel):
    message: str
    max_tokens: int = 512
    temperature: float = 0.7

@app.get("/health")
async def health():
    return {"status": "ok", "llm_backend": LLAMA_URL}

@app.get("/v1/models")
async def models():
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            r = await client.get(f"{LLAMA_URL}/v1/models")
            return r.json()
        except Exception as e:
            raise HTTPException(status_code=503, detail=str(e))

@app.post("/v1/chat")
async def chat(req: ChatRequest):
    payload = {
        "model": "qwen3",
        "messages": [{"role": "user", "content": req.message}],
        "max_tokens": req.max_tokens,
        "temperature": req.temperature,
        "stream": False
    }
    async with httpx.AsyncClient(timeout=120.0) as client:
        try:
            r = await client.post(
                f"{LLAMA_URL}/v1/chat/completions",
                json=payload
            )
            return r.json()
        except Exception as e:
            raise HTTPException(status_code=503, detail=str(e))

@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    """OpenAI-compatible passthrough"""
    body = await request.json()
    async with httpx.AsyncClient(timeout=120.0) as client:
        try:
            r = await client.post(
                f"{LLAMA_URL}/v1/chat/completions",
                json=body
            )
            return r.json()
        except Exception as e:
            raise HTTPException(status_code=503, detail=str(e))
