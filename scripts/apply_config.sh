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

# Instance overlay (optional). A deployment that adds to the reference stack, such as a vessel with its own
# MCP servers, keeps those additions in its own repository and points UPLIFT_INSTANCE_DIR at them:
#   instance.env                  sourced here: UPLIFT_EXTRA_MCP_BUNDLES (e.g. ', "vessel"'),
#                                 UPLIFT_GATEWAY_HOST, UPLIFT_GATEWAY_ALLOW_PUBLIC_BIND (operator only;
#                                 the admin agent's gateway and tools stay as the reference sets them)
#   zeroclaw-<tier>.overlay.toml  appended to that tier's rendered config: new tables only, such as
#                                 [mcp_bundles.<name>] and [[mcp.servers]] entries (keys already in the
#                                 template cannot be set again)
# Without it, the reference configuration renders unchanged.
UPLIFT_INSTANCE_DIR="${UPLIFT_INSTANCE_DIR:-}"
if [ -n "$UPLIFT_INSTANCE_DIR" ]; then
    [ -d "$UPLIFT_INSTANCE_DIR" ] || { echo "UPLIFT_INSTANCE_DIR=$UPLIFT_INSTANCE_DIR is not a directory" >&2; exit 1; }
    if [ -f "$UPLIFT_INSTANCE_DIR/instance.env" ]; then
        echo "Loading instance settings from $UPLIFT_INSTANCE_DIR/instance.env..."
        set -a
        source "$UPLIFT_INSTANCE_DIR/instance.env"
        set +a
    fi
fi

# Default variables
: "${VLLM_SERVED_MODEL_NAME:=gemma-4-26b-a4b}"
: "${UPLIFT_EXTRA_MCP_BUNDLES:=}"
: "${UPLIFT_GATEWAY_HOST:=127.0.0.1}"
: "${UPLIFT_GATEWAY_ALLOW_PUBLIC_BIND:=false}"
export UPLIFT_EXTRA_MCP_BUNDLES UPLIFT_GATEWAY_HOST UPLIFT_GATEWAY_ALLOW_PUBLIC_BIND
: "${VLLM_API_KEY:=}"
export VLLM_SERVED_MODEL_NAME
export VLLM_API_KEY

# Render a comma-separated list as quoted TOML array items.
# Sourcing .env strips the quotes users write ("U123","U456"), and the
# templates splice the value into allowed_users = [...], so unquoted IDs
# would produce invalid TOML. Accepts U123,U456 or "U123", "U456" or "*".
quote_list() {
    local raw="${1//\"/}" item out=""
    raw="${raw//\'/}"
    IFS=',' read -ra items <<< "$raw"
    for item in "${items[@]}"; do
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        [ -n "$item" ] && out+="${out:+, }\"${item}\""
    done
    printf '%s' "$out"
}
SLACK_ALLOWED_OPERATOR_USERS="$(quote_list "${SLACK_ALLOWED_OPERATOR_USERS:-}")"
SLACK_ALLOWED_ADMIN_USERS="$(quote_list "${SLACK_ALLOWED_ADMIN_USERS:-}")"
export SLACK_ALLOWED_OPERATOR_USERS SLACK_ALLOWED_ADMIN_USERS

SUBST_VARS='${VLLM_API_KEY} ${SLACK_OPERATOR_APP_TOKEN} ${SLACK_OPERATOR_BOT_TOKEN} ${SLACK_ALLOWED_OPERATOR_USERS} ${SLACK_ADMIN_APP_TOKEN} ${SLACK_ADMIN_BOT_TOKEN} ${SLACK_ALLOWED_ADMIN_USERS} ${BRAVE_SEARCH_API_KEY} ${VLLM_SERVED_MODEL_NAME} ${UPLIFT_EXTRA_MCP_BUNDLES} ${UPLIFT_GATEWAY_HOST} ${UPLIFT_GATEWAY_ALLOW_PUBLIC_BIND}'

# Helper function to bootstrap an agent tier
bootstrap_agent() {
    local tier=$1
    # .zeroclaw-<tier>/ is the ZeroClaw install root (config schema V3). ZeroClaw
    # creates data/, shared/ and agents/default/workspace/ under it on first start.
    local target_dir="${WORKSPACE_ROOT}/.zeroclaw-${tier}"
    local template="configs/zeroclaw-${tier}.toml.template"

    echo "--- Bootstrapping ${tier} Agent ---"

    # 1. Create directories (the trace mount too, so Docker does not create it as root)
    # agents/default/workspace is pre-created because the admin container bind-mounts
    # the operator's workspace, and Docker would otherwise create it owned by root.
    mkdir -p "${target_dir}/agents/default/workspace" "${WORKSPACE_ROOT}/traces/${tier}"
    
    # 2. Template configuration
    echo "Templating config into ${target_dir}/config.toml..."
    # Paired gateway devices are written into config.toml by ZeroClaw at runtime (encrypted). Carry them over
    # so that re-rendering does not unpair the dashboard.
    local paired=""
    [ -f "${target_dir}/config.toml" ] && paired="$(grep -m1 '^paired_tokens = ' "${target_dir}/config.toml" || true)"
    # The rendered config holds channel tokens: create it owner-only. The
    # agent containers run as the same UID, so they can still read it.
    (umask 077 && envsubst "$SUBST_VARS" < "${WORKSPACE_ROOT}/${template}" > "${target_dir}/config.toml")
    chmod 600 "${target_dir}/config.toml"
    if [ -n "$paired" ] && [ "$paired" != "paired_tokens = []" ]; then
        local tmp="${target_dir}/config.toml.tmp"
        awk -v line="$paired" '$0 == "paired_tokens = []" && !done { print line; done = 1; next } { print }' \
            "${target_dir}/config.toml" > "$tmp" && mv "$tmp" "${target_dir}/config.toml"
        chmod 600 "${target_dir}/config.toml"
        echo "Kept the gateway's paired devices."
    fi
    local overlay="${UPLIFT_INSTANCE_DIR:+${UPLIFT_INSTANCE_DIR}/zeroclaw-${tier}.overlay.toml}"
    if [ -n "$overlay" ] && [ -f "$overlay" ]; then
        echo "Appending instance overlay $overlay..."
        { printf '\n# --- instance overlay: %s ---\n' "$overlay"; envsubst "$SUBST_VARS" < "$overlay"; } >> "${target_dir}/config.toml"
    fi
    # A key set twice (template and overlay) is a TOML error the agent would only report at start
    python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "${target_dir}/config.toml" \
        || { echo "Rendered ${target_dir}/config.toml is not valid TOML" >&2; exit 1; }
    # ZeroClaw v0.8.6+ refuses group- or world-readable SQLite databases
    find "${target_dir}/data" -maxdepth 3 -name '*.db*' -type f -exec chmod 600 {} + 2>/dev/null || true
    
    # 3. Copy AIEOS identity profile to config mount directory
    echo "Copying AIEOS identity configuration..."
    cp "${WORKSPACE_ROOT}/configs/bootstrap/identity-${tier}.json" "${target_dir}/identity.json"
}

# Run bootstrap for both tiers
bootstrap_agent "operator"
bootstrap_agent "admin"

echo "Configuration and workspace bootstrapping completed successfully!"
