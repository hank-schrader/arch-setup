#!/usr/bin/env bash
# ============================================================================
# 00-install-paru.sh — Bootstrap paru AUR helper
# Run this FIRST on a fresh Arch install (requires base-devel + git)
# ============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Ensure we're not root
[[ $EUID -eq 0 ]] && error "Do not run this script as root. Run as your normal user."

# Ensure base-devel and git are installed
info "Installing base-devel and git (if missing)..."
sudo pacman -S --needed --noconfirm base-devel git

# Clone and build paru
PARU_DIR=$(mktemp -d)
info "Cloning paru into $PARU_DIR..."
git clone https://aur.archlinux.org/paru.git "$PARU_DIR/paru"
cd "$PARU_DIR/paru"

info "Building and installing paru..."
makepkg -si --noconfirm

cd ~
rm -rf "$PARU_DIR"

# Verify
if command -v paru &>/dev/null; then
    info "paru installed successfully: $(paru --version | head -1)"
else
    error "paru installation failed."
fi

info "Done! You can now run the next scripts."
