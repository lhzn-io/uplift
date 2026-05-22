#!/usr/bin/env bash
# scripts/env.sh — export VLLM_* env vars for a given model choice.
#
# Sourced by start_stack.sh, and meant to be sourced by the operator before
# running one-off docker-compose commands or scripts/verify_stack.sh that
# reference docker-compose.yml (which refers to VLLM_MODEL, VLLM_IMAGE, etc).
#
# Usage (shell):
#   source scripts/env.sh              # defaults to gemma4
#   source scripts/env.sh nemotron     # Nemotron-3-Nano
#
# Usage (inside another script):
#   source "${SCRIPT_DIR}/scripts/env.sh" "${MODEL_CHOICE:-gemma4}"

MODEL_CHOICE="${1:-gemma4}"

if [ "${MODEL_CHOICE}" = "nemotron" ]; then
    export VLLM_IMAGE="ghcr.io/nvidia-ai-iot/vllm:latest-jetson-orin"
    export VLLM_MODEL="stelterlab/NVIDIA-Nemotron-3-Nano-30B-A3B-AWQ"
    export VLLM_SERVED_MODEL_NAME="nvidia/nemotron-3-nano-30b-a3b"
    export VLLM_GPU_MEMORY_UTILIZATION="0.75"
    export VLLM_EXTRA_ARGS="--max-model-len 65536 --enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser-plugin /data/models/nemotron-30b-fp8/nano_v3_reasoning_parser.py --reasoning-parser nano_v3 --default-chat-template-kwargs {\"enable_thinking\":false}"
elif [ "${MODEL_CHOICE}" = "gemma4" ]; then
    export GEMMA4_REPO="cyankiwi/gemma-4-26B-A4B-it-AWQ-4bit"
    export GEMMA4_SNAPSHOT="4033b16200f4152e55e100ea12dc388c537df622"
    
    export VLLM_IMAGE="ghcr.io/nvidia-ai-iot/vllm:gemma4-jetson-orin"
    export VLLM_MODEL="${GEMMA4_REPO}"
    export VLLM_SERVED_MODEL_NAME="gemma-4-26b-a4b"
    export VLLM_GPU_MEMORY_UTILIZATION="0.8"
    export VLLM_EXTRA_ARGS="--enable-auto-tool-choice --reasoning-parser gemma4 --tool-call-parser gemma4 "
    export HF_HUB_OFFLINE=1
    export TRANSFORMERS_OFFLINE=1
    export HF_DATASETS_OFFLINE=1
else
    printf 'scripts/env.sh: unknown MODEL_CHOICE %q (expected gemma4|nemotron)\n' "${MODEL_CHOICE}" >&2
    return 1 2>/dev/null || exit 1
fi
