#!/usr/bin/env bash
# ============================================================================
# preflight-checks.sh — Validate host prerequisites before running installers
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

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
else
    error "Cannot read /etc/os-release."
fi

[[ "${ID:-}" == "arch" ]] || error "This setup is designed for Arch Linux. Detected: ${PRETTY_NAME:-unknown}."

command -v sudo >/dev/null 2>&1 || error "sudo is required."
if ! sudo -v; then
    error "sudo authentication failed."
fi

if command -v paru >/dev/null 2>&1; then
    info "paru detected: $(paru --version | head -1)"
else
    warn "paru not found yet (expected before running 00-install-paru.sh)."
fi

if grep -qE '^\[multilib\]' /etc/pacman.conf; then
    info "multilib repository is enabled."
else
    warn "multilib repository is not enabled. 01-system-packages.sh will enable it."
fi

if [[ -d /boot/loader/entries ]]; then
    info "Detected systemd-boot entries at /boot/loader/entries."
elif [[ -d /boot/grub ]]; then
    warn "Detected GRUB. Update GRUB kernel cmdline manually for NVIDIA options."
else
    warn "Bootloader layout not detected (neither systemd-boot entries nor /boot/grub)."
fi

if command -v lspci >/dev/null 2>&1; then
    if lspci | grep -qi 'NVIDIA'; then
        info "NVIDIA GPU detected."
    else
        warn "No NVIDIA GPU detected. Skip 02-nvidia-setup.sh on non-NVIDIA hosts."
    fi
else
    warn "lspci not available; GPU detection skipped."
fi

if ! getent hosts archlinux.org >/dev/null 2>&1; then
    warn "DNS/network lookup for archlinux.org failed."
else
    info "Network name resolution looks good."
fi

info "Preflight checks complete."
