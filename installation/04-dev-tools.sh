#!/usr/bin/env bash
# ============================================================================
# 04-dev-tools.sh — Install developer toolchains
#   Rust (via rustup), Node (via nvm), Bun, pnpm, Go, Java, C/C++, CMake
# Run AFTER 01-system-packages.sh
# ============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -eq 0 ]] && error "Do not run as root."

# ── Dev packages from repos ──────────────────────────────────────────────────
info "Installing dev packages from repos..."
paru -S --needed --noconfirm \
    clang \
    cmake \
    go \
    jdk-openjdk \
    python-pip \
    python-requests \
    nvm \
    pnpm \
    rocksdb \
    glfw \
    glm

# ── Rust (via rustup) ────────────────────────────────────────────────────────
info "Installing Rust via rustup..."

if command -v rustup &>/dev/null; then
    info "rustup already installed, updating..."
    rustup update
else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    source "$HOME/.cargo/env"
fi

# Install additional toolchains matching your current setup
info "Installing additional Rust toolchains..."
rustup toolchain install stable
rustup toolchain install nightly

# Install common cargo tools
info "Installing cargo tools..."
cargo install cargo-watch cargo-tauri websocat 2>/dev/null || warn "Some cargo installs may have failed"

# Rust analyzer (via rustup)
rustup component add rust-analyzer rust-src clippy rustfmt

# ── Node.js (via nvm) ────────────────────────────────────────────────────────
info "Setting up Node.js via nvm..."

export NVM_DIR="$HOME/.config/nvm"
# nvm is installed as a pacman package, source it
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    source "$NVM_DIR/nvm.sh"
elif [[ -s "/usr/share/nvm/nvm.sh" ]]; then
    source "/usr/share/nvm/nvm.sh"
    # Set up config dir
    mkdir -p "$NVM_DIR"
fi

if command -v nvm &>/dev/null; then
    info "Installing Node.js LTS..."
    nvm install --lts
    nvm use --lts
    nvm alias default lts/*
    info "Node.js $(node --version) installed."
else
    warn "nvm not available. Source it manually: source /usr/share/nvm/nvm.sh"
fi

# ── Bun ──────────────────────────────────────────────────────────────────────
info "Installing Bun..."

if command -v bun &>/dev/null; then
    info "Bun already installed: $(bun --version)"
    bun upgrade || true
else
    curl -fsSL https://bun.sh/install | bash
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
    info "Bun installed: $(bun --version)"
fi

# ── Docker Compose (plugin is installed via docker-buildx package) ───────────
info "Verifying Docker setup..."
paru -S --needed --noconfirm docker docker-buildx

if command -v docker &>/dev/null; then
    info "Docker: $(docker --version)"
    info "Docker Compose: $(docker compose version 2>/dev/null || echo 'plugin missing')"
fi

info "Developer tools installation complete!"
echo ""
info "Installed toolchains:"
echo "  Rust:   $(rustc --version 2>/dev/null || echo 'restart shell')"
echo "  Node:   $(node --version 2>/dev/null || echo 'restart shell')"
echo "  Bun:    $(bun --version 2>/dev/null || echo 'restart shell')"
echo "  pnpm:   $(pnpm --version 2>/dev/null || echo 'restart shell')"
echo "  Go:     $(go version 2>/dev/null || echo 'restart shell')"
echo "  Java:   $(java --version 2>/dev/null | head -1 || echo 'restart shell')"
echo "  GCC:    $(gcc --version 2>/dev/null | head -1 || echo 'restart shell')"
echo "  Clang:  $(clang --version 2>/dev/null | head -1 || echo 'restart shell')"
echo "  CMake:  $(cmake --version 2>/dev/null | head -1 || echo 'restart shell')"
echo "  Docker: $(docker --version 2>/dev/null || echo 'restart shell')"
