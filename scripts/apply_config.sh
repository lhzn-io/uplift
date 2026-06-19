#!/bin/bash
# apply_config.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${WORKSPACE_ROOT}/.env"

echo "Applying Agent configuration and bootstrapping workspaces..."

# Load environment variables if .env exists
if [ -f "$ENV_FILE" ]; then
    echo "Loading secrets from .env..."
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "Warning: .env file not found at $ENV_FILE. Will rely on exported environment variables."
fi

# Default variables
: "${VLLM_SERVED_MODEL_NAME:=gemma-4-26b-a4b}"
: "${VLLM_API_KEY:=}"
export VLLM_SERVED_MODEL_NAME
export VLLM_API_KEY

SUBST_VARS='${VLLM_API_KEY} ${SLACK_OPERATOR_APP_TOKEN} ${SLACK_OPERATOR_BOT_TOKEN} ${SLACK_ALLOWED_OPERATOR_USERS} ${SLACK_ADMIN_APP_TOKEN} ${SLACK_ADMIN_BOT_TOKEN} ${SLACK_ALLOWED_ADMIN_USERS} ${BRAVE_SEARCH_API_KEY} ${VLLM_SERVED_MODEL_NAME}'

# Helper function to bootstrap an agent tier
bootstrap_agent() {
    local tier=$1
    local target_dir="${WORKSPACE_ROOT}/.zeroclaw-${tier}"
    local workspace_dir="${target_dir}/workspace"
    local template="configs/zeroclaw-${tier}.toml.template"
    
    echo "--- Bootstrapping ${tier} Agent ---"
    
    # 1. Create directories
    mkdir -p "${workspace_dir}"
    
    # 2. Template configuration
    echo "Templating config into ${target_dir}/config.toml..."
    envsubst "$SUBST_VARS" < "${WORKSPACE_ROOT}/${template}" > "${target_dir}/config.toml"
    
    # 3. Copy AIEOS identity profile to config mount directory
    echo "Copying AIEOS identity configuration..."
    cp "${WORKSPACE_ROOT}/configs/bootstrap/identity-${tier}.json" "${target_dir}/identity.json"
}

# Run bootstrap for both tiers
bootstrap_agent "operator"
bootstrap_agent "admin"

echo "Configuration and workspace bootstrapping completed successfully!"
