#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "Setting model to Nemotron-3-Nano..."

if [ -f .env ]; then
    grep -v '^VLLM_' .env | grep -v '^TRANSFORMERS_OFFLINE' | grep -v '^HF_DATASETS_OFFLINE' > .env.tmp || true
else
    touch .env.tmp
fi

cat << 'ENVEOF' >> .env.tmp
VLLM_IMAGE=ghcr.io/nvidia-ai-iot/vllm:latest-jetson-orin
VLLM_MODEL=stelterlab/NVIDIA-Nemotron-3-Nano-30B-A3B-AWQ
VLLM_SERVED_MODEL_NAME=nemotron-3-nano
VLLM_GPU_MEMORY_UTILIZATION=0.8
VLLM_EXTRA_ARGS=
TRANSFORMERS_OFFLINE=1
HF_DATASETS_OFFLINE=1
ENVEOF

mv .env.tmp .env
