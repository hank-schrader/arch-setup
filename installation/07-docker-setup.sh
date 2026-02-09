#!/usr/bin/env bash
# ============================================================================
# 07-docker-setup.sh — Docker post-install configuration
# Run AFTER 03-services-and-users.sh
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

# Ensure docker packages are installed
info "Ensuring Docker packages..."
paru -S --needed --noconfirm docker docker-buildx

# Add user to docker group (may already be done by 03)
if getent group docker >/dev/null; then
    sudo usermod -aG docker "$USER"
else
    warn "Group docker not found (skipping usermod)."
fi

# Enable and start services
info "Enabling Docker services..."
for svc in docker.service containerd.service; do
    if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
        sudo systemctl enable "$svc"
    else
        warn "Service not found: $svc (skipping)"
    fi
done

if systemctl list-unit-files docker.service >/dev/null 2>&1; then
    sudo systemctl start docker.service 2>/dev/null || warn "Docker may already be running or needs reboot."
fi

# Verify
info "Verifying Docker installation..."
if docker info &>/dev/null; then
    info "Docker is running: $(docker --version)"
    info "Docker Compose: $(docker compose version)"
else
    warn "Docker daemon not reachable. You may need to log out and back in (for group membership) or reboot."
fi

info "Docker setup complete!"
