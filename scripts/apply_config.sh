#!/bin/bash
# apply_config.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${WORKSPACE_ROOT}/.env"
TEMPLATE_FILE="${WORKSPACE_ROOT}/configs/zeroclaw.toml.template"
TARGET_CONFIG="${WORKSPACE_ROOT}/.zeroclaw/config.toml"

echo "Applying configuration patches..."

# Load environment variables if .env exists
if [ -f "$ENV_FILE" ]; then
    echo "Loading secrets from .env..."
    # Export vars strictly to avoid leaking other settings unintentionally
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "Warning: .env file not found at $ENV_FILE. Will rely on exported environment variables."
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file $TEMPLATE_FILE not found."
    exit 1
fi

# Default the served model name to the Gemma4 baseline if the caller hasn't
# set it (e.g. apply_config.sh invoked outside start_stack.sh). start_stack.sh
# overrides this when --model nemotron is passed.
: "${VLLM_SERVED_MODEL_NAME:=gemma-4-26b-a4b}"
export VLLM_SERVED_MODEL_NAME

echo "Templating config into $TARGET_CONFIG (model=${VLLM_SERVED_MODEL_NAME})..."
mkdir -p "$(dirname "$TARGET_CONFIG")"

# Restrict envsubst to the known-safe variables so it doesn't mangle any
# unrelated $ syntax elsewhere in the template.
envsubst '${SLACK_APP_TOKEN} ${SLACK_BOT_TOKEN} ${BRAVE_SEARCH_API_KEY} ${VLLM_SERVED_MODEL_NAME}' < "$TEMPLATE_FILE" > "$TARGET_CONFIG"

echo "Configuration patched successfully!"
