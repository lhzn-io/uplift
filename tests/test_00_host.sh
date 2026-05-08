#!/usr/bin/env bash
# tests/test_00_host.sh — Host prerequisite integrity checks
# Verifies that the Jetson host is correctly prepared for zeroclaw.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

suite "host-prerequisites"

# br_netfilter
if lsmod | grep -q br_netfilter; then
    pass "br_netfilter loaded"
else
    fail "br_netfilter loaded" "module not present — run provision_orin.sh"
fi

# bridge-nf-call-iptables
val="$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null || echo '')"
#!/usr/bin/env bash
# tests/test_00_host.sh — Host prerequisite integrity checks
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

suite "host-prerequisites"

if lsmod | grep -q br_netfilter; then
    pass "br_netfilter loaded"
else
    fail "br_netfilter loaded" "module not present — run provision_orin.sh"
fi

val="$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null || echo '')"
if [[ "${val}" == "1" ]]; then
    pass "net.bridge.bridge-nf-call-iptables=1"
else
    fail "net.bridge.bridge-nf-call-iptables=1" "value='${val}'"
fi

val6="$(sysctl -n net.bridge.bridge-nf-call-ip6tables 2>/dev/null || echo '')"
if [[ "${val6}" == "1" ]]; then
    pass "net.bridge.bridge-nf-call-ip6tables=1"
else
    fail "net.bridge.bridge-nf-call-ip6tables=1" "value='${val6}'"
fi

iptables_ver="$(iptables --version 2>/dev/null || echo '')"
if echo "${iptables_ver}" | grep -qi 'legacy\|xtables'; then
    pass "iptables backend: legacy"
else
    fail "iptables backend: legacy" "got: ${iptables_ver}"
fi

daemon_json="$(cat /etc/docker/daemon.json 2>/dev/null || echo '{}')"
if echo "${daemon_json}" | python3 -c \
    "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('default-cgroupns-mode')=='host' else 1)" \
    2>/dev/null; then
    pass "docker default-cgroupns-mode=host"
else
    fail "docker default-cgroupns-mode=host" "daemon.json missing setting"
fi

if docker info >/dev/null 2>&1; then
    pass "docker daemon reachable"
else
    fail "docker daemon reachable"
fi

if docker info 2>/dev/null | grep -qi nvidia; then
    pass "nvidia container runtime registered"
else
    fail "nvidia container runtime registered" "check: sudo nvidia-ctk runtime configure --runtime=docker"
fi

swap_bytes="$(swapon --bytes --noheadings --show=SIZE 2>/dev/null | awk '{sum += $1} END {printf "%.0f\n", sum+0}')"
swap_bytes="${swap_bytes:-0}"
swap_gb=$(( swap_bytes / 1024 / 1024 / 1024 ))
if [[ "${swap_gb}" -ge 8 ]]; then
    pass "swap >= 8 GiB (${swap_gb} GiB)"
else
    fail "swap >= 8 GiB" "found ${swap_gb} GiB — zeroclaw recommends >= 8 GiB"
fi

suite_done
