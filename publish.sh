#!/usr/bin/env bash
# Builds and pushes the Docker image to GHCR.
# Usage: ./publish.sh [tag]   (default tag: latest)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    # shellcheck source=.env
    source "$SCRIPT_DIR/.env"
    set +a
else
    echo "ERROR: .env file not found. Copy .env.example and fill in your PAT."
    exit 1
fi

TAG="${1:-${TAG:-latest}}"
FULL_IMAGE="${IMAGE}:${TAG}"

echo "======================================================"
echo "  Publishing $FULL_IMAGE"
echo "======================================================"

# Login
echo "$CR_PAT" | docker login ghcr.io -u "$GITHUB_USER" --password-stdin

# Build
docker build -t "$FULL_IMAGE" "$SCRIPT_DIR"

# Push
docker push "$FULL_IMAGE"

echo ""
echo "Done. RunPod image: $FULL_IMAGE"
