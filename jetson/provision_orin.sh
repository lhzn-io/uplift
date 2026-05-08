#!/bin/bash
# provision_orin.sh - Jetson Orin Host Provisioner
#
# Run once after flash. Sets up hardware tuning, swap, Docker/NVIDIA runtime,
# and all host prerequisites required by zeroclaw.
#
# Must be run before scripts/install_zeroclaw.sh.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf '\n[WARN] %s\n' "$*" >&2; }
die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Hardware tuning
# ---------------------------------------------------------------------------
log "Tuning hardware (max power mode, jetson_clocks)"
sudo nvpmodel -m 0 || warn "nvpmodel not available — skipping"
sudo jetson_clocks   || warn "jetson_clocks not available — skipping"

# ---------------------------------------------------------------------------
# 2. Swap (64 GiB — required by zeroclaw onboarding on memory-limited systems)
# ---------------------------------------------------------------------------
log "Configuring swap"
if [ ! -f /swapfile ]; then
    sudo fallocate -l 64G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
    printf '  Swap created: /swapfile (64 GiB)\n'
else
    printf '  Swap already present — skipping\n'
fi

# ---------------------------------------------------------------------------
# 3. Docker + NVIDIA container runtime
# ---------------------------------------------------------------------------
log "Configuring Docker NVIDIA runtime"
sudo nvidia-ctk runtime configure --runtime=docker

# zeroclaw requires Docker to use host cgroup namespace mode.
# Without this, k3s inside the gateway container cannot manage pod cgroups.
log "Setting Docker cgroupns mode to host"
DOCKER_DAEMON_JSON=/etc/docker/daemon.json
if ! sudo python3 -c "
import json, sys
with open('${DOCKER_DAEMON_JSON}') as f:
    d = json.load(f)
sys.exit(0 if d.get('default-cgroupns-mode') == 'host' else 1)
" 2>/dev/null; then
    sudo python3 -c "
import json
try:
    f = open('${DOCKER_DAEMON_JSON}')
    d = json.load(f)
    f.close()
except Exception:
    d = {}
d['default-cgroupns-mode'] = 'host'
with open('${DOCKER_DAEMON_JSON}', 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
"
    printf '  Set default-cgroupns-mode=host in %s\n' "${DOCKER_DAEMON_JSON}"
else
    printf '  default-cgroupns-mode=host already set — skipping\n'
fi

sudo systemctl restart docker
printf '  Docker restarted\n'

# ---------------------------------------------------------------------------
# 4. zeroclaw host prerequisites
#    (br_netfilter, bridge sysctls, iptables-legacy backend)
#    The iptables-legacy fix is the critical Jetson-specific change:
#    JetPack 6 / 5.15 Tegra kernel does not support nf_tables properly.
# ---------------------------------------------------------------------------
log "Configuring host networking prerequisites"

sudo modprobe br_netfilter

cat << 'SYSCTL' | sudo tee /etc/sysctl.d/99-zeroclaw-k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
SYSCTL
sudo sysctl --system

# Switch to iptables-legacy for k3s compatibility
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

# ---------------------------------------------------------------------------
# 5. Verify critical bits
# ---------------------------------------------------------------------------
log "Verifying host state"
printf '  br_netfilter: '
lsmod | grep -q br_netfilter && printf 'loaded\n' || warn "br_netfilter NOT loaded"

printf '  bridge-nf-call-iptables: '
sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null || warn "sysctl not readable"

printf '  iptables backend: '
iptables --version

printf '  Docker cgroupns mode: '
docker info 2>/dev/null | grep -i 'cgroup' | head -2 || warn "docker info failed"

# ---------------------------------------------------------------------------
log "Provisioning complete. Reboot recommended before running install_zeroclaw.sh"
echo ""
echo "  Next steps:"
echo "    sudo reboot"
echo "    # After reboot:"
echo "    ./scripts/install_zeroclaw.sh"
