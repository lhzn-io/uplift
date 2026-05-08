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

cat << 'ENVEOF' >> .env.tmp
VLLM_IMAGE=ghcr.io/nvidia-ai-iot/vllm:gemma4-jetson-orin
VLLM_MODEL=cyankiwi/gemma-4-26B-A4B-it-AWQ-4bit
VLLM_SERVED_MODEL_NAME=gemma-4-26b-a4b
VLLM_GPU_MEMORY_UTILIZATION=0.8
VLLM_EXTRA_ARGS="--enable-auto-tool-choice --reasoning-parser gemma4 --tool-call-parser gemma4 --quantization compressed-tensors"
TRANSFORMERS_OFFLINE=0
HF_DATASETS_OFFLINE=0
ENVEOF

mv .env.tmp .env
