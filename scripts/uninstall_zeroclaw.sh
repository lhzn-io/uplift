#!/usr/bin/env bash
# uninstall_zeroclaw.sh - Remove ZeroClaw from the system

set -Eeuo pipefail

echo "================================================================"
echo " Uninstalling ZeroClaw..."
echo "================================================================"

echo "Stopping any running ZeroClaw processes..."
pkill -f zeroclaw || true

echo "Removing ZeroClaw binary..."
rm -f ~/.cargo/bin/zeroclaw

echo "Removing ZeroClaw configuration and data directory..."
rm -rf ~/.zeroclaw

echo ""
echo "ZeroClaw has been fully uninstalled."
