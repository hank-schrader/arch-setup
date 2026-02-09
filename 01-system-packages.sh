#!/usr/bin/env bash
# ============================================================================
# 01-system-packages.sh — Install all pacman + AUR packages via paru
# Run AFTER 00-install-paru.sh
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
command -v paru &>/dev/null || error "paru not found. Run 00-install-paru.sh first."

# ── Core system ──────────────────────────────────────────────────────────────
CORE_PACKAGES=(
    base
    base-devel
    linux
    linux-headers
    linux-firmware
    amd-ucode
    btrfs-progs
    efibootmgr
    smartmontools
    sof-firmware
)

# ── Networking ───────────────────────────────────────────────────────────────
NETWORK_PACKAGES=(
    networkmanager
    network-manager-applet
    iwd
    wireless_tools
    bind
    dnsmasq
    net-tools
    nmap
    proxychains-ng
    wget
)

# ── Bluetooth ────────────────────────────────────────────────────────────────
BLUETOOTH_PACKAGES=(
    bluez
    bluez-utils
    blueman
)

# ── Audio (PipeWire) ─────────────────────────────────────────────────────────
AUDIO_PACKAGES=(
    pipewire
    pipewire-alsa
    pipewire-jack
    pipewire-pulse
    wireplumber
    libpulse
    gst-plugin-pipewire
)

# ── NVIDIA (open kernel modules) ─────────────────────────────────────────────
NVIDIA_PACKAGES=(
    nvidia-open
    nvidia-utils
    lib32-nvidia-utils
    libva-nvidia-driver
    egl-wayland
    egl-gbm
    egl-x11
    linux-firmware-nvidia
)

# ── Vulkan / GPU fallbacks ───────────────────────────────────────────────────
GPU_PACKAGES=(
    vulkan-intel
    vulkan-nouveau
    vulkan-radeon
    intel-media-driver
    libva-intel-driver
    xf86-video-amdgpu
    xf86-video-ati
    xf86-video-nouveau
)

# ── Hyprland + Wayland desktop ───────────────────────────────────────────────
DESKTOP_PACKAGES=(
    hyprland
    hyprpaper
    hyprlock
    hypridle
    hyprpicker
    hyprshot
    xdg-desktop-portal-hyprland
    xdg-utils
    uwsm
    waybar
    rofi
    wofi
    dunst
    grim
    slurp
    brightnessctl
    feh
    polkit-kde-agent
    qt5-graphicaleffects
    qt5-wayland
    qt6-wayland
    webkit2gtk-4.1
)

# ── Terminals ────────────────────────────────────────────────────────────────
TERMINAL_PACKAGES=(
    ghostty
    kitty
    foot
)

# ── Xorg (for XWayland + fallback) ───────────────────────────────────────────
XORG_PACKAGES=(
    xorg-server
    xorg-xinit
    xorg-xrandr
    xdotool
)

# ── File manager ─────────────────────────────────────────────────────────────
FILE_MANAGER_PACKAGES=(
    dolphin
)

# ── Fonts ────────────────────────────────────────────────────────────────────
FONT_PACKAGES=(
    ttf-jetbrains-mono-nerd
    ttf-hack-nerd
)

# ── CLI utilities ────────────────────────────────────────────────────────────
CLI_PACKAGES=(
    btop
    htop
    ripgrep
    fzf
    playerctl
    vim
    nano
    unzip
    zip
    git
)

# ── Gaming ───────────────────────────────────────────────────────────────────
GAMING_PACKAGES=(
    steam
    lutris
    gamemode
    protontricks
    wine
)

# ── Applications ─────────────────────────────────────────────────────────────
APP_PACKAGES=(
    firefox
    discord
    qbittorrent
    remmina
    virtualbox
    android-tools
    ansible-core
)

# ── Shell ────────────────────────────────────────────────────────────────────
SHELL_PACKAGES=(
    zsh
)

# ── Hybrid GPU switching ─────────────────────────────────────────────────────
HYBRID_PACKAGES=(
    supergfxctl
)

# ── AUR packages (installed via paru) ────────────────────────────────────────
AUR_PACKAGES=(
    google-chrome
    grimblast-git
    heroic-games-launcher
    postman-bin
    protonup-qt
    simplescreenrecorder
    sublime-text-4
    downgrade
    droidcam
    rate-mirrors
)

# ──────────────────────────────────────────────────────────────────────────────
# Combine all official repo packages
# ──────────────────────────────────────────────────────────────────────────────
ALL_PACKAGES=(
    "${CORE_PACKAGES[@]}"
    "${NETWORK_PACKAGES[@]}"
    "${BLUETOOTH_PACKAGES[@]}"
    "${AUDIO_PACKAGES[@]}"
    "${NVIDIA_PACKAGES[@]}"
    "${GPU_PACKAGES[@]}"
    "${DESKTOP_PACKAGES[@]}"
    "${TERMINAL_PACKAGES[@]}"
    "${XORG_PACKAGES[@]}"
    "${FILE_MANAGER_PACKAGES[@]}"
    "${FONT_PACKAGES[@]}"
    "${CLI_PACKAGES[@]}"
    "${GAMING_PACKAGES[@]}"
    "${APP_PACKAGES[@]}"
    "${SHELL_PACKAGES[@]}"
    "${HYBRID_PACKAGES[@]}"
)

info "Configuring pacman..."
sudo sed -i -E 's/^#?ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
sudo sed -i -E 's/^#Color/Color/' /etc/pacman.conf

if grep -qE '^\[multilib\]' /etc/pacman.conf; then
    info "multilib is already enabled."
elif grep -qE '^#\[multilib\]' /etc/pacman.conf; then
    info "Enabling multilib repository..."
    sudo sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
else
    info "Adding multilib repository..."
    cat <<'EOF' | sudo tee -a /etc/pacman.conf >/dev/null

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
fi

info "Refreshing package databases and upgrading system..."
sudo pacman -Syu --noconfirm

info "Installing official repo packages (${#ALL_PACKAGES[@]} packages)..."
paru -S --needed --noconfirm "${ALL_PACKAGES[@]}" || warn "Some packages may have failed — check output above."

info "Installing AUR packages (${#AUR_PACKAGES[@]} packages)..."
paru -S --needed --noconfirm "${AUR_PACKAGES[@]}" || warn "Some AUR packages may have failed — check output above."

info "Package installation complete!"
