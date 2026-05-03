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

COPY requirements-cosmos.txt /tmp/requirements-cosmos.txt
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --python /opt/venv-cosmos/bin/python \
        -r /tmp/requirements-cosmos.txt

# ---------------------------------------------------------------------------- #
# gpt-oss venv — current vLLM release with GPT-OSS support                   #
# ---------------------------------------------------------------------------- #
RUN uv venv --seed /opt/venv-gptoss

COPY requirements-gptoss.txt /tmp/requirements-gptoss.txt

# Use uv's torch backend resolver so vLLM gets a CUDA-compatible torch build.
RUN uv pip install --python /opt/venv-gptoss/bin/python \
        --no-cache \
        --torch-backend=auto \
        -r /tmp/requirements-gptoss.txt

RUN test -x /opt/venv-cosmos/bin/hf && test -x /opt/venv-gptoss/bin/hf

# ---------------------------------------------------------------------------- #
# proxy venv — FastAPI router on port 8000                                     #
# ---------------------------------------------------------------------------- #
RUN uv venv /opt/venv-proxy

COPY proxy/requirements.txt /tmp/requirements-proxy.txt
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --python /opt/venv-proxy/bin/python \
        -r /tmp/requirements-proxy.txt

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
