#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.vllm-proxy-venv"

echo "Uninstalling vLLM Proxy..."

systemctl --user stop vllm-proxy.service || true
systemctl --user disable vllm-proxy.service || true
rm -f "${HOME}/.config/systemd/user/vllm-proxy.service"
systemctl --user daemon-reload || true

if [ -d "${VENV_DIR}" ]; then
    rm -rf "${VENV_DIR}"
fi

echo "Done."
