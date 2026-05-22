#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "Setting model to Gemma4 (gemma-4-26B-A4B-it-AWQ-4bit)..."

# Safely remove old model configs from .env if it exists
if [ -f .env ]; then
    grep -v '^VLLM_' .env | grep -v '^TRANSFORMERS_OFFLINE' | grep -v '^HF_DATASETS_OFFLINE' > .env.tmp || true
else
    touch .env.tmp
fi

# Source env.sh to get model identifiers
source "$(dirname "${BASH_SOURCE[0]}")/env.sh" gemma4

cat << ENVEOF >> .env.tmp
VLLM_IMAGE=${VLLM_IMAGE}
VLLM_MODEL=${GEMMA4_REPO}
VLLM_SERVED_MODEL_NAME=${VLLM_SERVED_MODEL_NAME}
VLLM_GPU_MEMORY_UTILIZATION=${VLLM_GPU_MEMORY_UTILIZATION}
VLLM_EXTRA_ARGS="${VLLM_EXTRA_ARGS} --quantization compressed-tensors"
HF_HUB_OFFLINE=${HF_HUB_OFFLINE}
TRANSFORMERS_OFFLINE=${TRANSFORMERS_OFFLINE}
HF_DATASETS_OFFLINE=${HF_DATASETS_OFFLINE}
ENVEOF

mv .env.tmp .env
