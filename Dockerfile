# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES.
# SPDX-License-Identifier: Apache-2.0

ARG CUDA_VERSION=12.8.1
FROM nvidia/cuda:${CUDA_VERSION}-cudnn-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------- #
# System packages                                                               #
# ---------------------------------------------------------------------------- #
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        ffmpeg \
        git \
        git-lfs \
        gpg \
        lsb-release \
        tree \
        wget \
        python3 \
        python3-venv && \
    git lfs install

# ---------------------------------------------------------------------------- #
# uv — fast Python package manager                                              #
# ---------------------------------------------------------------------------- #
COPY --from=ghcr.io/astral-sh/uv:0.8.12 /uv /uvx /usr/local/bin/
ENV UV_LINK_MODE=copy

# ---------------------------------------------------------------------------- #
# cosmos venv  — vllm >= 0.11.0 for Cosmos-Reason2 (Qwen3-VL based)           #
# ---------------------------------------------------------------------------- #
RUN uv venv /opt/venv-cosmos

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --python /opt/venv-cosmos/bin/python \
        "vllm>=0.11.0" \
        "transformers>=4.57.0" \
        "accelerate" \
        "huggingface_hub[cli]"

# ---------------------------------------------------------------------------- #
# gpt-oss venv — vllm==0.10.1+gptoss custom fork required by openai/gpt-oss   #
# ---------------------------------------------------------------------------- #
RUN uv venv /opt/venv-gptoss

# Install torch from nightly cu128 first (required by gptoss vllm fork)
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --python /opt/venv-gptoss/bin/python \
        torch \
        --index-url https://download.pytorch.org/whl/nightly/cu128

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --python /opt/venv-gptoss/bin/python \
        transformers \
        kernels

# Install the gpt-oss custom vllm wheel
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --python /opt/venv-gptoss/bin/python \
        --pre "vllm==0.10.1+gptoss" \
        --extra-index-url https://wheels.vllm.ai/gpt-oss/ \
        --extra-index-url https://download.pytorch.org/whl/nightly/cu128 \
        --index-strategy unsafe-best-match

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --python /opt/venv-gptoss/bin/python \
        "huggingface_hub[cli]"

# ---------------------------------------------------------------------------- #
# proxy venv — FastAPI router on port 8000                                     #
# ---------------------------------------------------------------------------- #
RUN uv venv /opt/venv-proxy

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --python /opt/venv-proxy/bin/python \
        "fastapi" \
        "uvicorn[standard]" \
        "httpx"

# ---------------------------------------------------------------------------- #
# Environment                                                                   #
# ---------------------------------------------------------------------------- #
# Triton bundled ptxas doesn't support the latest GPU architectures
ENV TRITON_PTXAS_PATH=/usr/local/cuda/bin/ptxas

WORKDIR /workspace

# ---------------------------------------------------------------------------- #
# Application files                                                             #
# ---------------------------------------------------------------------------- #
COPY scripts/ /workspace/scripts/
COPY proxy/   /workspace/proxy/
COPY entrypoint.sh /workspace/entrypoint.sh

RUN chmod +x /workspace/entrypoint.sh /workspace/scripts/*.sh

EXPOSE 8000

ENTRYPOINT ["/workspace/entrypoint.sh"]
CMD ["/bin/bash"]
