#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.vllm-proxy-venv"
PROXY_SCRIPT="${SCRIPT_DIR}/vllm_proxy.py"
REQ_FILE="${SCRIPT_DIR}/vllm_proxy_requirements.txt"
USER_NAME="$(whoami)"

echo "Installing vLLM Proxy to ${VENV_DIR}"

if ! command -v uv &> /dev/null; then
    echo "uv not found, installing via pip..."
    pip3 install uv
fi

uv venv "${VENV_DIR}"
uv pip install --python "${VENV_DIR}" -r "${REQ_FILE}"

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

echo "Done. Service 'vllm-proxy' established."
