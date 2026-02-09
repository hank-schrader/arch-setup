#!/usr/bin/env bash
# ============================================================================
# 06-configs.sh — Deploy all dotfiles and application configs
#   Hyprland, Hyprpaper, Hyprlock, Ghostty, Foot, Rofi
# Run AFTER packages are installed
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

get_connected_monitors() {
    local hypr_output connector status_file status_value
    local -a monitors=()
    local -A seen=()

    if command -v hyprctl >/dev/null 2>&1; then
        hypr_output="$(hyprctl monitors 2>/dev/null || true)"
        if [[ -n "$hypr_output" ]]; then
            while IFS= read -r connector; do
                [[ -z "$connector" || -n "${seen[$connector]:-}" ]] && continue
                seen["$connector"]=1
                monitors+=("$connector")
            done < <(awk '/^Monitor / {print $2}' <<< "$hypr_output")
        fi
    fi

    if [[ ${#monitors[@]} -eq 0 ]] && command -v xrandr >/dev/null 2>&1; then
        while IFS= read -r connector; do
            [[ -z "$connector" || -n "${seen[$connector]:-}" ]] && continue
            seen["$connector"]=1
            monitors+=("$connector")
        done < <(xrandr --query 2>/dev/null | awk '/ connected/ {print $1}')
    fi

    if [[ ${#monitors[@]} -eq 0 ]]; then
        for status_file in /sys/class/drm/card*-*/status; do
            [[ -f "$status_file" ]] || continue
            status_value="$(<"$status_file")"
            [[ "$status_value" == "connected" ]] || continue

            connector="${status_file%/status}"
            connector="${connector##*/}"
            connector="${connector#*-}"
            [[ -z "$connector" || -n "${seen[$connector]:-}" ]] && continue
            seen["$connector"]=1
            monitors+=("$connector")
        done
    fi

    printf '%s\n' "${monitors[@]}"
}

build_hypr_monitor_lines() {
    local hypr_output main_monitor monitor
    local -a monitors=()

    if command -v hyprctl >/dev/null 2>&1; then
        hypr_output="$(hyprctl monitors 2>/dev/null || true)"
        if [[ -n "$hypr_output" ]]; then
            main_monitor="$(awk '
                /^Monitor / {mon=$2}
                /focused: yes/ {print mon; exit}
            ' <<< "$hypr_output")"
        fi
    fi

    mapfile -t monitors < <(get_connected_monitors)

    if [[ ${#monitors[@]} -gt 0 ]]; then
        if [[ -z "$main_monitor" ]]; then
            main_monitor="${monitors[0]}"
        fi

        printf 'monitor=%s,preferred,0x0,1\n' "$main_monitor"
        for monitor in "${monitors[@]}"; do
            [[ "$monitor" == "$main_monitor" ]] && continue
            printf 'monitor=%s,preferred,auto,1\n' "$monitor"
        done
        return
    fi

    # Fallback for first boot / non-Hyprland sessions.
    printf 'monitor=,preferred,auto,1\n'
}

build_hyprpaper_wallpaper_blocks() {
    local wallpaper_path="$1" monitor
    local -a monitors=()

    mapfile -t monitors < <(get_connected_monitors)

    if [[ ${#monitors[@]} -eq 0 ]]; then
        cat << EOF
wallpaper {
    monitor =
    path = $wallpaper_path
}
EOF
        return
    fi

    for monitor in "${monitors[@]}"; do
        cat << EOF
wallpaper {
    monitor = $monitor
    path = $wallpaper_path
}

EOF
    done
}

[[ $EUID -eq 0 ]] && error "Do not run as root."

# ── Hyprland ─────────────────────────────────────────────────────────────────
info "Writing Hyprland config..."
mkdir -p "$HOME/.config/hypr"
backup_file "$HOME/.config/hypr/hyprland.conf"

cat > "$HOME/.config/hypr/hyprland.conf" << 'HYPRCONF'
################
### MONITORS ###
################

__MONITOR_LINES__

###################
### MY PROGRAMS ###
###################

$fileManager = dolphin
$terminal = ghostty
$menu = wofi --show drun

#################
### AUTOSTART ###
#################

exec-once = hyprpaper

#############################
### ENVIRONMENT VARIABLES ###
#############################

env = XCURSOR_SIZE,24
env = HYPRCURSOR_SIZE,24
env = LIBVA_DRIVER_NAME,nvidia
env = XDG_SESSION_TYPE,wayland
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia

#####################
### LOOK AND FEEL ###
#####################

general {
    gaps_in = 3
    gaps_out = 5
    border_size = 0
    col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
    col.inactive_border = rgba(595959aa)
    resize_on_border = false
    allow_tearing = false
    layout = dwindle
}

decoration {
    rounding = 10
    rounding_power = 2
    active_opacity = 1.0
    inactive_opacity = 1.0

    shadow {
        enabled = true
        range = 4
        render_power = 3
        color = rgba(1a1a1aee)
    }

    blur {
        enabled = true
        size = 3
        passes = 1
        vibrancy = 0.1696
    }
}

animations {
    enabled = yes, please :)

    bezier = easeOutQuint,   0.23, 1,    0.32, 1
    bezier = easeInOutCubic, 0.65, 0.05, 0.36, 1
    bezier = linear,         0,    0,    1,    1
    bezier = almostLinear,   0.5,  0.5,  0.75, 1
    bezier = quick,          0.15, 0,    0.1,  1

    animation = global,        1,     10,    default
    animation = border,        1,     5.39,  easeOutQuint
    animation = windows,       1,     4.79,  easeOutQuint
    animation = windowsIn,     1,     4.1,   easeOutQuint, popin 87%
    animation = windowsOut,    1,     1.49,  linear,       popin 87%
    animation = fadeIn,        1,     1.73,  almostLinear
    animation = fadeOut,       1,     1.46,  almostLinear
    animation = fade,          1,     3.03,  quick
    animation = layers,        1,     3.81,  easeOutQuint
    animation = layersIn,      1,     4,     easeOutQuint, fade
    animation = layersOut,     1,     1.5,   linear,       fade
    animation = fadeLayersIn,  1,     1.79,  almostLinear
    animation = fadeLayersOut, 1,     1.39,  almostLinear
    animation = workspaces,    1,     1.94,  almostLinear, fade
    animation = workspacesIn,  1,     1.21,  almostLinear, fade
    animation = workspacesOut, 1,     1.94,  almostLinear, fade
    animation = zoomFactor,    1,     7,     quick
}

dwindle {
    pseudotile = true
    preserve_split = true
}

master {
    new_status = master
}

misc {
    force_default_wallpaper = 0
    disable_hyprland_logo = true
}

#############
### INPUT ###
#############

input {
    kb_layout = us,ru
    kb_variant =
    kb_model =
    kb_options =
    kb_rules =
    follow_mouse = 1
    sensitivity = 0

    touchpad {
        natural_scroll = true
    }
}

gesture = 3, horizontal, workspace

device {
    name = epic-mouse-v1
    sensitivity = -0.5
}

###################
### KEYBINDINGS ###
###################

$mainMod = SUPER

bind = SUPER, Q, killactive
bind = SUPER, T, exec, ghostty
bind = SUPER, A, exec, rofi -show drun
bind = SUPER, L, exec, hyprlock
bind = SUPER, F, fullscreen
bind = ALT, TAB, cyclenext
bind = SUPER, SPACE, exec, hyprctl switchxkblayout current next
bind = SUPER, PRINT, exec, hyprshot -m region -o __SCREENSHOT_DIR__

bind = $mainMod, RETURN, exec, $terminal
bind = $mainMod, M, exit,
bind = $mainMod, E, exec, $fileManager
bind = $mainMod, V, togglefloating,
bind = $mainMod, P, pseudo,
bind = $mainMod, J, togglesplit,

# Move focus
bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d

# Workspaces
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod, 0, workspace, 10

# Move to workspace
bind = $mainMod SHIFT, 1, movetoworkspacesilent, 1
bind = $mainMod SHIFT, 2, movetoworkspacesilent, 2
bind = $mainMod SHIFT, 3, movetoworkspacesilent, 3
bind = $mainMod SHIFT, 4, movetoworkspacesilent, 4
bind = $mainMod SHIFT, 5, movetoworkspacesilent, 5
bind = $mainMod SHIFT, 6, movetoworkspacesilent, 6
bind = $mainMod SHIFT, 7, movetoworkspacesilent, 7
bind = $mainMod SHIFT, 8, movetoworkspacesilent, 8
bind = $mainMod SHIFT, 9, movetoworkspacesilent, 9
bind = $mainMod SHIFT, 0, movetoworkspacesilent, 10

# Scratchpad
bind = $mainMod, S, togglespecialworkspace, magic
bind = $mainMod SHIFT, S, movetoworkspace, special:magic

# Mouse
bind = $mainMod, mouse_down, workspace, e+1
bind = $mainMod, mouse_up, workspace, e-1
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Media keys
bindel = ,XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+
bindel = ,XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindel = ,XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindel = ,XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
bindel = ,XF86MonBrightnessUp, exec, brightnessctl -e4 -n2 set 5%+
bindel = ,XF86MonBrightnessDown, exec, brightnessctl -e4 -n2 set 5%-

# Player controls
bindl = , XF86AudioNext, exec, playerctl next
bindl = , XF86AudioPause, exec, playerctl play-pause
bindl = , XF86AudioPlay, exec, playerctl play-pause
bindl = , XF86AudioPrev, exec, playerctl previous
HYPRCONF

monitor_lines="$(build_hypr_monitor_lines)"
awk -v monitor_lines="$monitor_lines" '
    $0 == "__MONITOR_LINES__" {print monitor_lines; next}
    {print}
' "$HOME/.config/hypr/hyprland.conf" > "$HOME/.config/hypr/hyprland.conf.tmp"
mv "$HOME/.config/hypr/hyprland.conf.tmp" "$HOME/.config/hypr/hyprland.conf"

sed -i "s|__SCREENSHOT_DIR__|$HOME/Pictures/screenshots|g" "$HOME/.config/hypr/hyprland.conf"

# ── Hyprlock ─────────────────────────────────────────────────────────────────
info "Writing Hyprlock config..."
backup_file "$HOME/.config/hypr/hyprlock.conf"

cat > "$HOME/.config/hypr/hyprlock.conf" << 'HYPRLOCK'
# BACKGROUND
background {
    monitor =
    blur_passes = 2
    contrast = 1
    brightness = 0.5
    vibrancy = 0.2
    vibrancy_darkness = 0.2
}

# GENERAL
general {
    no_fade_in = true
    no_fade_out = true
    hide_cursor = false
    grace = 0
    disable_loading_bar = true
}

# INPUT FIELD
input-field {
    monitor =
    size = 250, 60
    outline_thickness = 2
    dots_size = 0.2
    dots_spacing = 0.35
    dots_center = true
    outer_color = rgba(0, 0, 0, 0)
    inner_color = rgba(0, 0, 0, 0.2)
    font_color = rgba(242, 243, 244, 0.9)
    fade_on_empty = false
    rounding = -1
    check_color = rgb(204, 136, 34)
    placeholder_text = <i><span foreground="#cdd6f4">Input Password...</span></i>
    hide_input = false
    position = 0, -200
    halign = center
    valign = center
}

# DATE
label {
    monitor =
    text = cmd[update:1000] echo "$(date +"%A, %B %d")"
    color = rgba(242, 243, 244, 0.75)
    font_size = 22
    font_family = JetBrains Mono
    position = 0, 300
    halign = center
    valign = center
}

# TIME
label {
    monitor =
    text = cmd[update:1000] echo "$(date +"%-I:%M")"
    color = rgba(242, 243, 244, 0.75)
    font_size = 95
    font_family = JetBrains Mono Extrabold
    position = 0, 200
    halign = center
    valign = center
}
HYPRLOCK

# ── Hyprpaper ────────────────────────────────────────────────────────────────
info "Writing Hyprpaper config..."
backup_file "$HOME/.config/hypr/hyprpaper.conf"

wallpaper_path="$HOME/Pictures/wallpaper2.png"
hyprpaper_wallpaper_blocks="$(build_hyprpaper_wallpaper_blocks "$wallpaper_path")"

cat > "$HOME/.config/hypr/hyprpaper.conf" << HYPRPAPER
preload = $wallpaper_path

$hyprpaper_wallpaper_blocks
splash = false
HYPRPAPER

# ── Ghostty ──────────────────────────────────────────────────────────────────
info "Writing Ghostty config..."
mkdir -p "$HOME/.config/ghostty"
backup_file "$HOME/.config/ghostty/config"

cat > "$HOME/.config/ghostty/config" << 'GHOSTTY'
working-directory = home
window-inherit-working-directory = false
command = "/usr/bin/zsh"
keybind = shift+enter=text:\x1b\r
GHOSTTY

# ── Foot ─────────────────────────────────────────────────────────────────────
info "Writing Foot config..."
mkdir -p "$HOME/.config/foot"
backup_file "$HOME/.config/foot/foot.ini"

cat > "$HOME/.config/foot/foot.ini" << 'FOOT'
shell=zsh
title=foot
font=JetBrains Mono Nerd Font:size=12
letter-spacing=0
dpi-aware=no
pad=25x25
bold-text-in-bright=no
gamma-correct-blending=no

[scrollback]
lines=100000

[cursor]
style=beam
beam-thickness=1.5

[colors]
alpha=1

[key-bindings]
scrollback-up-page=Page_Up
scrollback-down-page=Page_Down
search-start=Control+Shift+f

[search-bindings]
cancel=Escape
find-prev=Shift+F3
find-next=F3 Control+G
FOOT

# ── Rofi ─────────────────────────────────────────────────────────────────────
info "Writing Rofi config..."
mkdir -p "$HOME/.config/rofi"
backup_file "$HOME/.config/rofi/config.rasi"

cat > "$HOME/.config/rofi/config.rasi" << 'ROFI'
* {
    font: "Figtree 13";
    g-spacing: 10px;
    g-margin: 0;
    b-color: #000000FF;
    fg-color: #FFFFFFFF;
    fgp-color: #888888FF;
    b-radius: 8px;
    g-padding: 8px;
    hl-color: #FFFFFFFF;
    hlt-color: #000000FF;
    alt-color: #111111FF;
    wbg-color: #000000CC;
    w-border: 0px solid;
    w-border-color: #FFFFFFFF;
    w-padding: 12px;
}

configuration {
    modi: "drun";
    show-icons: true;
    display-drun: "";
}

listview {
    columns: 1;
    lines: 7;
    fixed-height: true;
    fixed-columns: true;
    cycle: false;
    scrollbar: false;
    border: 0px solid;
}

window {
    transparency: "real";
    width: 450px;
    border-radius: @b-radius;
    background-color: @wbg-color;
    border: @w-border;
    border-color: @w-border-color;
    padding: @w-padding;
}

prompt {
    text-color: @fg-color;
}

inputbar {
    children: ["prompt", "entry"];
    spacing: @g-spacing;
}

entry {
    placeholder: "Search Apps";
    text-color: @fg-color;
    placeholder-color: @fgp-color;
}

mainbox {
    spacing: @g-spacing;
    margin: @g-margin;
    padding: @g-padding;
    children: ["inputbar", "listview", "message"];
}

element {
    spacing: @g-spacing;
    margin: @g-margin;
    padding: @g-padding;
    border: 0px solid;
    border-radius: @b-radius;
    border-color: @b-color;
    background-color: transparent;
    text-color: @fg-color;
}

element normal.normal {
    background-color: transparent;
    text-color: @fg-color;
}

element alternate.normal {
    background-color: @alt-color;
    text-color: @fg-color;
}

element selected.active {
    background-color: @hl-color;
    text-color: @hlt-color;
}

element selected.normal {
    background-color: @hl-color;
    text-color: @hlt-color;
}

message {
    background-color: red;
    border: 0px solid;
}
ROFI

# ── Screenshots directory ───────────────────────────────────────────────────
mkdir -p "$HOME/Pictures/screenshots"

info "All configs deployed!"
