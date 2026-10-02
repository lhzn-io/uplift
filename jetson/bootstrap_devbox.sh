#!/usr/bin/env bash
# bootstrap_devbox.sh - Turn a freshly provisioned Jetson into an uplift development box
#
# Run after jetson/provision_orin.sh. Safe to re-run: every step checks its own
# state first, so a second run changes nothing.
#
# The node must hold no state that exists only here. Everything this script sets
# up is reproducible, and the only secret involved (GitHub access) is created
# interactively by `gh auth login`, never stored in the repository. A reflash
# followed by provision_orin.sh and this script restores the development setup.
#
# Installs:
#   - C build dependencies for the ZeroClaw crates
#   - GitHub CLI (gh), used as the git credential helper for the https submodules
#   - rustup, with the toolchain pinned in rust-toolchain.toml
# Configures:
#   - git identity (only if unset)
#   - submodules, once gh is authenticated
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Optional: set the git identity on first run, e.g.
#   GIT_USER_NAME="Jane Doe" GIT_USER_EMAIL="jane@example.org" ./jetson/bootstrap_devbox.sh
GIT_USER_NAME="${GIT_USER_NAME:-}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-}"

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf '\n[WARN] %s\n' "$*" >&2; }
die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Build dependencies
# ---------------------------------------------------------------------------
log "Checking build dependencies"
APT_PKGS=(build-essential pkg-config libssl-dev clang cmake git curl ca-certificates)
MISSING=()
for pkg in "${APT_PKGS[@]}"; do
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" || MISSING+=("$pkg")
done
if [ "${#MISSING[@]}" -gt 0 ]; then
    printf '  Installing: %s\n' "${MISSING[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends "${MISSING[@]}"
else
    printf '  All present - skipping\n'
fi

# ---------------------------------------------------------------------------
# 2. GitHub CLI (official apt repository)
# ---------------------------------------------------------------------------
log "Checking GitHub CLI"
if ! command -v gh >/dev/null 2>&1; then
    KEYRING=/etc/apt/keyrings/githubcli-archive-keyring.gpg
    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo tee "$KEYRING" >/dev/null
    sudo chmod go+r "$KEYRING"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=${KEYRING}] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y gh
else
    printf '  %s - skipping\n' "$(gh --version | head -n 1)"
fi

# ---------------------------------------------------------------------------
# 3. Rust toolchain (user-level, ~/.cargo)
#    The channel comes from rust-toolchain.toml at the repository root, which
#    also applies to builds inside stack/zeroclaw.
# ---------------------------------------------------------------------------
log "Checking Rust toolchain"
export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v rustup >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain none --profile minimal --no-modify-path
fi
if ! grep -q '.cargo/env' "$HOME/.bashrc" 2>/dev/null; then
    echo '. "$HOME/.cargo/env"' >> "$HOME/.bashrc"
    printf '  Added ~/.cargo/env to ~/.bashrc\n'
fi
(cd "$REPO_ROOT" && rustup toolchain install)
(cd "$REPO_ROOT" && printf '  %s\n' "$(rustc --version)")

# ---------------------------------------------------------------------------
# 4. Git identity
#    Commits from this box should be authored by the person making them,
#    so the identity is supplied by the caller rather than defaulted here.
# ---------------------------------------------------------------------------
log "Checking git identity"
if [ -z "$(git config --global --get user.name || true)" ] && [ -n "$GIT_USER_NAME" ]; then
    git config --global user.name "$GIT_USER_NAME"
fi
if [ -z "$(git config --global --get user.email || true)" ] && [ -n "$GIT_USER_EMAIL" ]; then
    git config --global user.email "$GIT_USER_EMAIL"
fi
if git config --global --get user.email >/dev/null 2>&1; then
    printf '  %s\n' "$(git var GIT_AUTHOR_IDENT | sed 's/ [0-9]* [-+][0-9]*$//')"
else
    warn "No git identity set. Re-run with GIT_USER_NAME and GIT_USER_EMAIL before committing."
fi

# ---------------------------------------------------------------------------
# 5. GitHub access and submodules
#    No SSH key lives on the node. gh acts as the git credential helper for
#    the https submodule URLs in .gitmodules.
# ---------------------------------------------------------------------------
log "Checking GitHub access"
if gh auth status >/dev/null 2>&1; then
    gh auth setup-git
    cd "$REPO_ROOT"
    git submodule sync --quiet
    # Initialize only submodules that are not checked out yet. A plain
    # `git submodule update` would also move existing checkouts back to the
    # recorded commit, detaching any local branch work in progress.
    UNINIT=$(git submodule status | awk '/^-/ {print $2}')
    if [ -n "$UNINIT" ]; then
        # shellcheck disable=SC2086
        git submodule update --init -- $UNINIT
    else
        printf '  Submodules already initialized - skipping\n'
    fi
    git submodule status
else
    warn "gh is not authenticated, so submodules were not fetched."
    echo "  Run this interactively, then re-run this script:"
    echo "    gh auth login --hostname github.com --git-protocol https --web"
fi

log "Development box bootstrap complete"
