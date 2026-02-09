#!/usr/bin/env bash
# ============================================================================
# bootstrap.sh — Auto-generated. Download & run all setup scripts.
# ============================================================================
set -euo pipefail

SERVER="${1:?Usage: bash bootstrap.sh <server_ip:port>}"

GREEN='\033[0;32m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }

DEST="$HOME/arch-setup"
mkdir -p "$DEST"

SCRIPTS=(
    preflight-checks.sh
    00-install-paru.sh
    01-system-packages.sh
    02-nvidia-setup.sh
    03-services-and-users.sh
    04-dev-tools.sh
    05-shell-setup.sh
    06-configs.sh
    07-docker-setup.sh
    install-all.sh
)

info "Downloading scripts from $SERVER into $DEST ..."

for s in "${SCRIPTS[@]}"; do
    info "  -> $s"
    curl -fsSL "http://$SERVER/$s" -o "$DEST/$s"
    chmod +x "$DEST/$s"
done

echo ""
info "All scripts downloaded to $DEST"
info ""
info "To install everything:"
info "  cd $DEST && ./install-all.sh"
info ""
info "Or run scripts individually:"
info "  cd $DEST && ./00-install-paru.sh"
