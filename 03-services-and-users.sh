#!/usr/bin/env bash
# ============================================================================
# 03-services-and-users.sh — Enable system services, user groups, display mgr
# Run AFTER 02-nvidia-setup.sh
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

USERNAME="${USER}"

# ── System services ──────────────────────────────────────────────────────────
info "Enabling system services..."

system_services=(
    NetworkManager.service
    NetworkManager-dispatcher.service
    NetworkManager-wait-online.service
    bluetooth.service
    docker.service
    containerd.service
    systemd-timesyncd.service
)

for svc in "${system_services[@]}"; do
    if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
        sudo systemctl enable "$svc"
    else
        warn "Service not found: $svc (skipping)"
    fi
done

# ── User services (run as user, no sudo) ─────────────────────────────────────
info "Enabling user services..."

if systemctl --user show-environment >/dev/null 2>&1; then
    user_services=(
        pipewire.service
        pipewire.socket
        pipewire-pulse.socket
        wireplumber.service
    )
    for svc in "${user_services[@]}"; do
        if systemctl --user list-unit-files "$svc" >/dev/null 2>&1; then
            systemctl --user enable "$svc"
        else
            warn "User service not found: $svc (skipping)"
        fi
    done
else
    warn "No user systemd session detected. Log in graphically and enable user services manually."
fi

# ── User groups ──────────────────────────────────────────────────────────────
info "Adding $USERNAME to required groups..."

for group in wheel video docker vboxusers; do
    if getent group "$group" >/dev/null; then
        sudo usermod -aG "$group" "$USERNAME"
    else
        warn "Group not found: $group (skipping)"
    fi
done

info "Services enabled, user groups configured."
info "You may need to log out and back in for group changes to take effect."
