#!/usr/bin/env bash
# install_zeroclaw.sh - Install the ZeroClaw Rust orchestrator

set -Eeuo pipefail

echo "================================================================"
echo " Bootstrapping ZeroClaw onto Jetson Orin..."
echo "================================================================"

git clone https://github.com/zeroclaw-labs/zeroclaw.git /tmp/zc
cd /tmp/zc
bash install.sh

echo "Building the ZeroClaw web dashboard..."
mkdir -p ~/.zeroclaw
cd web
npm ci
npm run build
cp -r dist ~/.zeroclaw/web_dist

cd - >/dev/null
rm -rf /tmp/zc

echo ""
echo "ZeroClaw installed successfully."
echo "You can now run: zeroclaw onboard"
