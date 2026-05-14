#!/usr/bin/env bash
# scripts/setup_agent_ssh.sh - Setup dedicated SSH keys for the ZeroClaw agent

set -Eeuo pipefail

SSH_DIR="$HOME/.zeroclaw/ssh"
KEY_FILE="$SSH_DIR/id_ed25519"

echo "Creating dedicated SSH directory at $SSH_DIR..."
mkdir -p "$SSH_DIR"

if [[ -f "$KEY_FILE" ]]; then
    echo "Agent key already exists at $KEY_FILE"
else
    echo "Generating new Ed25519 keypair for ZeroClaw agent..."
    ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -C "ZeroClaw Agent @ $(hostname)"
fi

echo ""
echo "================================================================"
echo " NEXT STEPS:"
echo "================================================================"
echo "1. Authorize this key on your remote hosts:"
echo "   ssh-copy-id -i ${KEY_FILE}.pub <user>@<remote-host>"
echo ""
echo "2. Ensure your docker-compose.yml mounts this directory:"
echo "   volumes:"
echo "     - ~/.zeroclaw/ssh:/zeroclaw-data/.ssh"
echo ""
echo "3. Restart the stack:"
echo "   ./stop_stack.sh zeroclaw && ./start_stack.sh"
echo "================================================================"
