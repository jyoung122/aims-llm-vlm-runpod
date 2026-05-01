#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Starts the gpt-oss-20b vLLM server on localhost:GPTOSS_PORT (internal only).
set -euo pipefail

GPTOSS_MODEL="${GPTOSS_MODEL:-openai/gpt-oss-20b}"
GPTOSS_PORT="${GPTOSS_PORT:-8002}"

# shellcheck source=/dev/null
source /opt/venv-gptoss/bin/activate

exec vllm serve "$GPTOSS_MODEL" \
    --host 127.0.0.1 \
    --port "$GPTOSS_PORT"
