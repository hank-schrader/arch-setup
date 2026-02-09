#!/usr/bin/env bash
# ============================================================================
# 05-shell-setup.sh — Zsh, Oh My Zsh, plugins, shell dotfiles
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

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
        cp -a "$file" "$backup"
        warn "Backed up $file -> $backup"
    fi
}

[[ $EUID -eq 0 ]] && error "Do not run as root."

# ── Install Oh My Zsh ────────────────────────────────────────────────────────
info "Installing Oh My Zsh..."

if [[ -d "$HOME/.oh-my-zsh" ]]; then
    info "Oh My Zsh already installed."
else
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# ── Install Zsh plugins ─────────────────────────────────────────────────────
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

info "Installing zsh-autosuggestions..."
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

info "Installing zsh-syntax-highlighting..."
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

# ── Write .zshrc ─────────────────────────────────────────────────────────────
info "Writing ~/.zshrc..."
backup_file "$HOME/.zshrc"

cat > "$HOME/.zshrc" << 'ZSHRC'
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

source "$ZSH/oh-my-zsh.sh"

export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
export NVM_DIR="$HOME/.config/nvm"
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
[ -s "/usr/share/nvm/init-nvm.sh" ] && . "/usr/share/nvm/init-nvm.sh"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

alias zed="zeditor"
alias battery='for f in /sys/class/power_supply/BAT*/capacity; do [[ -r "$f" ]] && cat "$f" && break; done'

[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
ZSHRC

# ── Write .bashrc ────────────────────────────────────────────────────────────
info "Writing ~/.bashrc..."
backup_file "$HOME/.bashrc"

cat > "$HOME/.bashrc" << 'BASHRC'
#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

export NVM_DIR="$HOME/.config/nvm"
[ -s "/usr/share/nvm/init-nvm.sh" ] && . "/usr/share/nvm/init-nvm.sh"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
BASHRC

# ── Write .bash_profile ─────────────────────────────────────────────────────
info "Writing ~/.bash_profile..."
backup_file "$HOME/.bash_profile"

cat > "$HOME/.bash_profile" << 'BASHPROFILE'
#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]] && . ~/.bashrc
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
if [[ -d "$HOME/Pictures/flutter/bin" ]]; then
    export PATH="$HOME/Pictures/flutter/bin:$PATH"
fi

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
BASHPROFILE

# ── Set default shell to zsh ────────────────────────────────────────────────
info "Setting default shell to zsh..."
if [[ "$SHELL" != */zsh ]]; then
    chsh -s /usr/bin/zsh
    info "Default shell changed to zsh. Log out and back in for it to take effect."
else
    info "Default shell is already zsh."
fi

info "Shell setup complete!"
