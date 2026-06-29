#!/usr/bin/env bash
# scripts/env.sh — export VLLM_* env vars.
#
# Sourced by start_stack.sh, and meant to be sourced by the operator before
# running one-off docker-compose commands or scripts/verify_stack.sh that
# reference docker-compose.yml (which refers to VLLM_MODEL, VLLM_IMAGE, etc).
#
# Usage (shell):
#   source scripts/env.sh

MODEL_CHOICE="${1:-gemma4-26b-a4b}"

# Normalize shorthands to full Hugging Face model paths
if [ "${MODEL_CHOICE}" = "gemma4-26b-a4b" ] || [ "${MODEL_CHOICE}" = "gemma4" ]; then
    MODEL_CHOICE="cyankiwi/gemma-4-26B-A4B-it-AWQ-4bit"
elif [ "${MODEL_CHOICE}" = "gemma4-12b" ]; then
    MODEL_CHOICE="cyankiwi/gemma-4-12B-it-AWQ-INT4"
elif [ "${MODEL_CHOICE}" = "nemotron3-30b-a3b" ] || [ "${MODEL_CHOICE}" = "nemotron" ]; then
    MODEL_CHOICE="stelterlab/NVIDIA-Nemotron-3-Nano-30B-A3B-AWQ"
fi

if [ "${MODEL_CHOICE}" = "stelterlab/NVIDIA-Nemotron-3-Nano-30B-A3B-AWQ" ]; then
    export VLLM_IMAGE="ghcr.io/nvidia-ai-iot/vllm:latest-jetson-orin"
    export VLLM_MODEL="/data/models/huggingface/hub/models--stelterlab--NVIDIA-Nemotron-3-Nano-30B-A3B-AWQ/snapshots/5db3a99a80bbc78bc06c363c607187125205b85d"
    export VLLM_SERVED_MODEL_NAME="nemotron-3-nano"
    export VLLM_GPU_MEMORY_UTILIZATION="0.75"
    export VLLM_EXTRA_ARGS="--max-model-len 65536 --enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser-plugin /data/models/nemotron-30b-fp8/nano_v3_reasoning_parser.py --reasoning-parser nano_v3 --default-chat-template-kwargs {\"enable_thinking\":false}"
elif [ "${MODEL_CHOICE}" = "cyankiwi/gemma-4-12B-it-AWQ-INT4" ]; then
    export GEMMA4_REPO="cyankiwi/gemma-4-12B-it-AWQ-INT4"
    export VLLM_IMAGE="ghcr.io/nvidia-ai-iot/vllm:gemma4-jetson-orin"
    export VLLM_MODEL="cyankiwi/gemma-4-12B-it-AWQ-INT4"
    export VLLM_SERVED_MODEL_NAME="gemma-4-12b-a4b"
    export VLLM_GPU_MEMORY_UTILIZATION="0.8"
    export VLLM_EXTRA_ARGS="--enable-auto-tool-choice --reasoning-parser gemma4 --tool-call-parser gemma4"
elif [ "${MODEL_CHOICE}" = "cyankiwi/gemma-4-26B-A4B-it-AWQ-4bit" ]; then
    export GEMMA4_REPO="cyankiwi/gemma-4-26B-A4B-it-AWQ-4bit"
    export GEMMA4_SNAPSHOT="4033b16200f4152e55e100ea12dc388c537df622"
    export VLLM_IMAGE="ghcr.io/nvidia-ai-iot/vllm:gemma4-jetson-orin"
    export VLLM_MODEL="/data/models/huggingface/hub/models--cyankiwi--gemma-4-26B-A4B-it-AWQ-4bit/snapshots/${GEMMA4_SNAPSHOT}"
    export VLLM_SERVED_MODEL_NAME="gemma-4-26b-a4b"
    export VLLM_GPU_MEMORY_UTILIZATION="0.8"
    export VLLM_EXTRA_ARGS="--enable-auto-tool-choice --reasoning-parser gemma4 --tool-call-parser gemma4"
    export HF_HUB_OFFLINE=1
    export TRANSFORMERS_OFFLINE=1
    export HF_DATASETS_OFFLINE=1
else
    # Support arbitrary/generic Hugging Face model paths!
    if [[ "${MODEL_CHOICE}" == */* ]]; then
        export VLLM_IMAGE="ghcr.io/nvidia-ai-iot/vllm:latest-jetson-orin" # default image
        export VLLM_MODEL="${MODEL_CHOICE}"
        # Extract the model basename as the served model name (e.g. gemma-4-12b-it-awq-int4)
        export VLLM_SERVED_MODEL_NAME="$(echo "${MODEL_CHOICE##*/}" | tr '[:upper:]' '[:lower:]')"
        export VLLM_GPU_MEMORY_UTILIZATION="0.8"
        export VLLM_EXTRA_ARGS="--enable-auto-tool-choice"
    else
        printf 'scripts/env.sh: unknown MODEL_CHOICE %q\n' "${MODEL_CHOICE}" >&2
        return 1 2>/dev/null || exit 1
    fi
fi
