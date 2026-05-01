#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Starts the cosmos-reason2 vLLM server on localhost:COSMOS_PORT (internal only).
set -euo pipefail

COSMOS_MODEL="${COSMOS_MODEL:-nvidia/Cosmos-Reason2-2B}"
COSMOS_PORT="${COSMOS_PORT:-8001}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-16384}"

# shellcheck source=/dev/null
source /opt/venv-cosmos/bin/activate

exec vllm serve "$COSMOS_MODEL" \
    --host 127.0.0.1 \
    --port "$COSMOS_PORT" \
    --reasoning-parser qwen3 \
    --max-model-len "$MAX_MODEL_LEN" \
    --allowed-local-media-path /workspace
