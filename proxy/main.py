"""
FastAPI proxy — routes /v1/* requests to the correct vLLM backend
based on the `model` field in the request body.

External port 8000 (single endpoint):
  POST /v1/chat/completions  →  routes by model name
  POST /v1/completions       →  routes by model name
  POST /v1/embeddings        →  routes by model name
  GET  /v1/models            →  merged list from both backends
  GET  /health               →  proxy health
"""
import json
import os

import httpx
from fastapi import FastAPI, Request, Response
from fastapi.responses import StreamingResponse

# ---------------------------------------------------------------------------- #
# Routing table (populated from env vars at import time)                        #
# ---------------------------------------------------------------------------- #
COSMOS_MODEL = os.environ.get("COSMOS_MODEL", "nvidia/Cosmos-Reason2-2B")
GPTOSS_MODEL = os.environ.get("GPTOSS_MODEL", "openai/gpt-oss-20b")
COSMOS_PORT = int(os.environ.get("COSMOS_PORT", "8001"))
GPTOSS_PORT = int(os.environ.get("GPTOSS_PORT", "8002"))

ROUTE_TABLE: dict[str, str] = {
    COSMOS_MODEL: f"http://127.0.0.1:{COSMOS_PORT}",
    GPTOSS_MODEL: f"http://127.0.0.1:{GPTOSS_PORT}",
}

app = FastAPI(title="Model Router")


# ---------------------------------------------------------------------------- #
# Helpers                                                                       #
# ---------------------------------------------------------------------------- #
def _forward_headers(request: Request) -> dict[str, str]:
    """Strip hop-by-hop headers that must not be forwarded."""
    skip = {"host", "content-length", "transfer-encoding", "connection"}
    return {k: v for k, v in request.headers.items() if k.lower() not in skip}


def _error(message: str, status: int = 404) -> Response:
    return Response(
        content=json.dumps(
            {"error": {"message": message, "type": "invalid_request_error"}}
        ),
        status_code=status,
        media_type="application/json",
    )


async def _resolve_backend(body: bytes) -> tuple[str | None, str | None]:
    """Return (backend_url, model_name) or (None, None) on unknown model."""
    try:
        model = json.loads(body).get("model", "")
    except (json.JSONDecodeError, AttributeError):
        model = ""
    backend = ROUTE_TABLE.get(model)
    return backend, model


# ---------------------------------------------------------------------------- #
# Routes                                                                        #
# ---------------------------------------------------------------------------- #
@app.get("/v1/models")
async def list_models() -> dict:
    """Fan out to both backends and return a merged model list."""
    results: list = []
    async with httpx.AsyncClient(timeout=10.0) as client:
        for url in ROUTE_TABLE.values():
            try:
                resp = await client.get(f"{url}/v1/models")
                results.extend(resp.json().get("data", []))
            except Exception:
                pass  # backend may still be loading
    return {"object": "list", "data": results}


async def _proxy(request: Request, path: str) -> Response:
    """Generic proxy handler — reads model from body, routes, streams."""
    body = await request.body()
    backend, model = await _resolve_backend(body)

    if not backend:
        available = list(ROUTE_TABLE.keys())
        return _error(
            f"Unknown model '{model}'. Available models: {available}", status=404
        )

    target_url = f"{backend}/{path}"
    headers = _forward_headers(request)

    try:
        is_stream = json.loads(body).get("stream", False)
    except Exception:
        is_stream = False

    if is_stream:
        async def generate():
            async with httpx.AsyncClient(timeout=None) as client:
                async with client.stream(
                    request.method, target_url, content=body, headers=headers
                ) as resp:
                    async for chunk in resp.aiter_bytes():
                        yield chunk

        return StreamingResponse(
            generate(),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )

    async with httpx.AsyncClient(timeout=300.0) as client:
        resp = await client.request(
            request.method, target_url, content=body, headers=headers
        )

    return Response(
        content=resp.content,
        status_code=resp.status_code,
        media_type=resp.headers.get("content-type", "application/json"),
    )


@app.post("/v1/chat/completions")
async def chat_completions(request: Request) -> Response:
    return await _proxy(request, "v1/chat/completions")


@app.post("/v1/completions")
async def completions(request: Request) -> Response:
    return await _proxy(request, "v1/completions")


@app.post("/v1/embeddings")
async def embeddings(request: Request) -> Response:
    return await _proxy(request, "v1/embeddings")


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}
