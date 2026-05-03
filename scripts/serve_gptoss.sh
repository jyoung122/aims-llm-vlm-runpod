#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Downloads the gpt-oss model from Hugging Face, then starts the vLLM server on
# localhost:GPTOSS_PORT (internal only).
set -euo pipefail

GPTOSS_MODEL="${GPTOSS_MODEL:-openai/gpt-oss-20b}"
GPTOSS_PORT="${GPTOSS_PORT:-8002}"
HF_HOME="${HF_HOME:-/workspace/models}"
HF_DOWNLOAD="${HF_DOWNLOAD:-1}"

export HF_HOME

# shellcheck source=/dev/null
source /opt/venv-gptoss/bin/activate

mkdir -p "$HF_HOME"

if [ "$HF_DOWNLOAD" != "0" ]; then
    echo "[download] Fetching $GPTOSS_MODEL from Hugging Face..."
    hf download "$GPTOSS_MODEL"
fi

exec vllm serve "$GPTOSS_MODEL" \
    --host 127.0.0.1 \
    --port "$GPTOSS_PORT"
