#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.vllm-proxy-venv"
PROXY_SCRIPT="${SCRIPT_DIR}/vllm_proxy.py"
REQ_FILE="${SCRIPT_DIR}/vllm_proxy_requirements.txt"
USER_NAME="$(whoami)"

echo "Installing vLLM Proxy to ${VENV_DIR}"

if command -v uv &> /dev/null; then
    uv venv "${VENV_DIR}"
    uv pip install --python "${VENV_DIR}" -r "${REQ_FILE}"
else
    # Ubuntu 24.04 marks the system Python as externally managed, so use a
    # plain venv (python3-venv) rather than pip-installing uv system-wide.
    python3 -m venv "${VENV_DIR}"
    "${VENV_DIR}/bin/pip" install --quiet -r "${REQ_FILE}"
fi

SERVICE_DIR="${HOME}/.config/systemd/user"
mkdir -p "${SERVICE_DIR}"
SERVICE_FILE="${SERVICE_DIR}/vllm-proxy.service"

cat << SVC > "${SERVICE_FILE}"
[Unit]
Description=vLLM Instrumentation Proxy

[Service]
Type=simple
WorkingDirectory=${SCRIPT_DIR}
ExecStart=${VENV_DIR}/bin/python ${PROXY_SCRIPT}
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
SVC

echo "Installing user systemd service..."
systemctl --user daemon-reload
systemctl --user enable vllm-proxy.service

# Without lingering, user services stop when the last login session ends.
if ! loginctl show-user "${USER_NAME}" -p Linger 2>/dev/null | grep -q "yes"; then
    sudo -n loginctl enable-linger "${USER_NAME}" 2>/dev/null \
        || echo "Note: run 'sudo loginctl enable-linger ${USER_NAME}' so the proxy survives logout."
fi

echo "Done. Service 'vllm-proxy' established (start_stack.sh starts it)."
