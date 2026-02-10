#!/usr/bin/env bash
# ============================================================================
# install-all.sh — Master installer: runs all setup scripts in order
#
# Usage:
#   ./install-all.sh          # Run everything
#   ./install-all.sh 04       # Resume from script 04
# ============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
header(){ echo -e "\n${CYAN}══════════════════════════════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}\n"; }

RAW_START_FROM="${1:-00}"
if [[ "$RAW_START_FROM" =~ ^[0-7]$ ]]; then
    START_FROM="$(printf "%02d" "$RAW_START_FROM")"
elif [[ "$RAW_START_FROM" =~ ^0[0-7]$ ]]; then
    START_FROM="$RAW_START_FROM"
else
    warn "Invalid start point: $RAW_START_FROM"
    warn "Use values from 00 to 07 (or 0 to 7)."
    exit 1
fi

SCRIPTS=(
    "00-install-paru.sh:Bootstrap paru AUR helper"
    "01-system-packages.sh:Install all system packages"
    "02-nvidia-setup.sh:Configure NVIDIA drivers & DRM"
    "03-services-and-users.sh:Enable services & user groups"
    "04-dev-tools.sh:Install developer toolchains"
    "05-shell-setup.sh:Configure Zsh & Oh My Zsh"
    "06-configs.sh:Deploy dotfiles & app configs"
    "07-docker-setup.sh:Docker post-install setup"
)

PRECHECK_SCRIPT="$SCRIPT_DIR/preflight-checks.sh"
if [[ -f "$PRECHECK_SCRIPT" ]]; then
    header "Preflight Checks"
    if bash "$PRECHECK_SCRIPT"; then
        info "Preflight checks passed."
    else
        warn "Preflight checks failed. Continue anyway? [y/N]"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 1
        fi
    fi
fi

MIRROR_SCRIPT="$SCRIPT_DIR/../dependency_region_selection/select-mirror.sh"
if [[ -f "$MIRROR_SCRIPT" ]]; then
    header "Mirror Selection"
    if bash "$MIRROR_SCRIPT"; then
        info "Mirror selection completed."
    else
        warn "Mirror selection failed. Continue with existing mirrors? [y/N]"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 1
        fi
    fi
fi

for entry in "${SCRIPTS[@]}"; do
    script="${entry%%:*}"
    desc="${entry#*:}"
    num="${script%%-*}"

    if [[ "$num" < "$START_FROM" ]]; then
        warn "Skipping $script (before start point $START_FROM)"
        continue
    fi

    script_path="$SCRIPT_DIR/$script"
    if [[ ! -f "$script_path" ]]; then
        warn "Script not found: $script_path — skipping."
        continue
    fi

    header "$script — $desc"

    if bash "$script_path"; then
        info "$script completed successfully."
    else
        warn "$script exited with errors. Continue? [y/N]"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Aborted. Resume later with: $0 $num"
            exit 1
        fi
    fi
done

echo ""
header "ALL DONE!"
info "System setup complete. Please reboot for all changes to take effect."
info "  sudo reboot"
