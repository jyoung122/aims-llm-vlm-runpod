#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Entrypoint: downloads models from HuggingFace, starts both vLLM backends
# and the FastAPI proxy router.
set -euo pipefail

# ---------------------------------------------------------------------------- #
# Config (override via RunPod env vars)                                         #
# ---------------------------------------------------------------------------- #
COSMOS_MODEL="${COSMOS_MODEL:-nvidia/Cosmos-Reason2-2B}"
GPTOSS_MODEL="${GPTOSS_MODEL:-openai/gpt-oss-20b}"
COSMOS_PORT="${COSMOS_PORT:-8001}"
GPTOSS_PORT="${GPTOSS_PORT:-8002}"
PORT="${PORT:-8000}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-16384}"
HF_HOME="${HF_HOME:-/workspace/models}"

export HF_HOME COSMOS_MODEL GPTOSS_MODEL COSMOS_PORT GPTOSS_PORT PORT MAX_MODEL_LEN

echo "======================================================"
echo "  Model Router — startup"
echo "======================================================"
echo "  COSMOS_MODEL : $COSMOS_MODEL  (port $COSMOS_PORT)"
echo "  GPTOSS_MODEL : $GPTOSS_MODEL  (port $GPTOSS_PORT)"
echo "  Proxy port   : $PORT"
echo "  HF_HOME      : $HF_HOME"
echo "======================================================"

mkdir -p "$HF_HOME"

# ---------------------------------------------------------------------------- #
# HuggingFace auth                                                              #
# ---------------------------------------------------------------------------- #
if [ -n "${HF_TOKEN:-}" ]; then
    echo "[auth] Logging in to HuggingFace..."
    /opt/venv-cosmos/bin/huggingface-cli login --token "$HF_TOKEN" --add-to-git-credential
fi

# ---------------------------------------------------------------------------- #
# Download models (skips files already cached)                                  #
# ---------------------------------------------------------------------------- #
echo "[download] Fetching $COSMOS_MODEL ..."
/opt/venv-cosmos/bin/huggingface-cli download "$COSMOS_MODEL"

echo "[download] Fetching $GPTOSS_MODEL ..."
/opt/venv-gptoss/bin/huggingface-cli download "$GPTOSS_MODEL"

# ---------------------------------------------------------------------------- #
# Start backends                                                                #
# ---------------------------------------------------------------------------- #
echo "[start] cosmos vLLM on port $COSMOS_PORT ..."
HF_DOWNLOAD=0 /workspace/scripts/serve_cosmos.sh &
COSMOS_PID=$!

echo "[start] gpt-oss vLLM on port $GPTOSS_PORT ..."
HF_DOWNLOAD=0 /workspace/scripts/serve_gptoss.sh &
GPTOSS_PID=$!

# ---------------------------------------------------------------------------- #
# Wait for backends to be healthy before opening the proxy                      #
# ---------------------------------------------------------------------------- #
wait_for_health() {
    local url="$1"
    local name="$2"
    local max_wait=720   # 12 minutes — model loading can be slow on first run
    local elapsed=0
    echo -n "[health] Waiting for $name ..."
    until curl -sf "$url/health" > /dev/null 2>&1; do
        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
        if [ "$elapsed" -ge "$max_wait" ]; then
            echo " TIMEOUT — $name did not become healthy in ${max_wait}s"
            exit 1
        fi
    done
    echo " ready"
}

wait_for_health "http://127.0.0.1:${COSMOS_PORT}" "cosmos ($COSMOS_MODEL)"
wait_for_health "http://127.0.0.1:${GPTOSS_PORT}" "gpt-oss ($GPTOSS_MODEL)"

# ---------------------------------------------------------------------------- #
# Graceful shutdown                                                             #
# ---------------------------------------------------------------------------- #
cleanup() {
    echo "[shutdown] Stopping backends..."
    kill "$COSMOS_PID" "$GPTOSS_PID" 2>/dev/null || true
    wait "$COSMOS_PID" "$GPTOSS_PID" 2>/dev/null || true
    echo "[shutdown] Done."
}
trap cleanup SIGTERM SIGINT

# ---------------------------------------------------------------------------- #
# Start the proxy (foreground — pod stays alive while proxy runs)               #
# ---------------------------------------------------------------------------- #
echo "[start] FastAPI proxy on 0.0.0.0:${PORT} ..."
exec /opt/venv-proxy/bin/uvicorn proxy.main:app \
    --host 0.0.0.0 \
    --port "$PORT" \
    --app-dir /workspace \
    --no-access-log
