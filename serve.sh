#!/usr/bin/env bash
# ============================================================================
# serve.sh — Start a local HTTP server to serve setup scripts
#
# On the NEW machine, run the one-liner printed by this script to download
# and execute everything.
#
# Usage:
#   ./serve.sh              # serve on port 8888
#   ./serve.sh 9999         # serve on custom port
# ============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

PORT="${1:-8888}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Get local IP ─────────────────────────────────────────────────────────────
get_local_ip() {
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1
}

LOCAL_IP="$(get_local_ip)"
if [[ -z "$LOCAL_IP" ]]; then
    LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi
[[ -z "$LOCAL_IP" ]] && LOCAL_IP="<YOUR_IP>"

# ── Generate bootstrap script that the new machine will download ─────────────
cat > "$SCRIPT_DIR/bootstrap.sh" << BOOTSTRAP
#!/usr/bin/env bash
# ============================================================================
# bootstrap.sh — Auto-generated. Download & run all setup scripts.
# ============================================================================
set -euo pipefail

SERVER="\${1:?Usage: bash bootstrap.sh <server_ip:port>}"

GREEN='\033[0;32m'
NC='\033[0m'
info() { echo -e "\${GREEN}[INFO]\${NC} \$*"; }

DEST="\$HOME/scripts"
mkdir -p "\$DEST"

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

info "Downloading scripts from \$SERVER into \$DEST ..."

for s in "\${SCRIPTS[@]}"; do
    info "  -> \$s"
    curl -fsSL "http://\$SERVER/\$s" -o "\$DEST/\$s"
    chmod +x "\$DEST/\$s"
done

echo ""
info "All scripts downloaded to \$DEST"
info ""
info "To install everything:"
info "  cd \$DEST && ./install-all.sh"
info ""
info "Or run scripts individually:"
info "  cd \$DEST && ./00-install-paru.sh"
BOOTSTRAP

chmod +x "$SCRIPT_DIR/bootstrap.sh"

# ── Print instructions ───────────────────────────────────────────────────────
clear 2>/dev/null || true

echo -e "${CYAN}"
echo "  ┌──────────────────────────────────────────────────────────────┐"
echo "  │              LOCAL SCRIPT SERVER                             │"
echo "  └──────────────────────────────────────────────────────────────┘"
echo -e "${NC}"
echo -e "  Serving ${BOLD}${SCRIPT_DIR}${NC} on port ${BOLD}${PORT}${NC}"
echo -e "  Local IP: ${BOLD}${LOCAL_IP}${NC}"
echo ""
echo -e "${CYAN}  ── On the new machine, run ONE of these: ──────────────────────${NC}"
echo ""
echo -e "  ${GREEN}# Option 1: Download all scripts, then run manually${NC}"
echo -e "  ${BOLD}curl -fsSL http://${LOCAL_IP}:${PORT}/bootstrap.sh | bash -s ${LOCAL_IP}:${PORT}${NC}"
echo ""
echo -e "  ${GREEN}# Option 2: Download + immediately start full install${NC}"
echo -e "  ${BOLD}curl -fsSL http://${LOCAL_IP}:${PORT}/bootstrap.sh | bash -s ${LOCAL_IP}:${PORT} && ~/scripts/install-all.sh${NC}"
echo ""
echo -e "  ${GREEN}# Option 3: Download a single script${NC}"
echo -e "  ${BOLD}curl -fsSL http://${LOCAL_IP}:${PORT}/00-install-paru.sh -o 00-install-paru.sh${NC}"
echo ""
echo -e "${CYAN}  ── Available files: ───────────────────────────────────────────${NC}"
echo ""
for f in "$SCRIPT_DIR"/*.sh; do
    echo "    http://${LOCAL_IP}:${PORT}/$(basename "$f")"
done
echo ""
echo -e "${YELLOW}  Press Ctrl+C to stop the server.${NC}"
echo ""

# ── Start server ─────────────────────────────────────────────────────────────
cd "$SCRIPT_DIR"
python3 -m http.server "$PORT" --bind 0.0.0.0
