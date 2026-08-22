#!/usr/bin/env bash
# ============================================================================
# 06-configs.sh — Deploy all dotfiles and application configs
#   Hyprland 0.55+ (Lua), Hyprpaper, Hyprlock, Ghostty, Foot, Rofi
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

lua_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

get_active_monitor_specs() {
    local hypr_output

    command -v hyprctl >/dev/null 2>&1 || return 0
    hypr_output="$(hyprctl monitors 2>/dev/null || true)"
    [[ -n "$hypr_output" ]] || return 0

    awk '
        function emit() {
            if (name != "") {
                printf "%s\t%s\t%s\t%s\t%s\n", name, mode, position, scale, transform
            }
        }

        /^Monitor / {
            emit()
            name = $2
            mode = "preferred"
            position = "auto"
            scale = "1"
            transform = "0"
            next
        }

        name != "" && /^[[:space:]]+[0-9]+x[0-9]+@[^[:space:]]+[[:space:]]+at[[:space:]]+/ {
            mode = $1
            position = $3
            next
        }

        name != "" && /^[[:space:]]+scale:/ {
            scale = $2
            next
        }

        name != "" && /^[[:space:]]+transform:/ {
            transform = $2
            next
        }

        END { emit() }
    ' <<< "$hypr_output"
}

build_hypr_monitor_lua() {
    local monitor mode position scale transform
    local -a monitors=()
    local active_specs

    active_specs="$(get_active_monitor_specs)"
    if [[ -n "$active_specs" ]]; then
        while IFS=$'\t' read -r monitor mode position scale transform; do
            [[ -n "$monitor" ]] || continue
            cat << EOF
hl.monitor({
    output = "$(lua_escape "$monitor")",
    mode = "$(lua_escape "$mode")",
    position = "$(lua_escape "$position")",
    scale = $scale,
    transform = $transform,
})

EOF
        done <<< "$active_specs"
        return
    fi

    mapfile -t monitors < <(get_connected_monitors)

    if [[ ${#monitors[@]} -gt 0 ]]; then
        for monitor in "${monitors[@]}"; do
            cat << EOF
hl.monitor({
    output = "$(lua_escape "$monitor")",
    mode = "preferred",
    position = "auto",
    scale = 1,
})

EOF
        done
        return
    fi

    # Fallback for first boot / non-Hyprland sessions.
    cat << 'EOF'
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})
EOF
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
command -v Hyprland >/dev/null 2>&1 || error "Hyprland is not installed. Run 01-system-packages.sh first."

hyprland_version="$(Hyprland --version 2>/dev/null | awk 'NR == 1 {print $2}' || true)"
[[ -n "$hyprland_version" ]] || error "Could not determine the installed Hyprland version."
if [[ "$(printf '%s\n' "0.55" "$hyprland_version" | sort -V | head -n 1)" != "0.55" ]]; then
    error "Hyprland $hyprland_version is too old for the generated Lua config (requires 0.55+)."
fi

info "Writing Hyprland $hyprland_version Lua config..."
mkdir -p "$HOME/.config/hypr"
backup_file "$HOME/.config/hypr/hyprland.lua"
backup_file "$HOME/.config/hypr/hyprland.conf"

hyprland_config="$HOME/.config/hypr/hyprland.lua"
hyprland_config_tmp="$HOME/.config/hypr/.hyprland.generated.lua"
trap 'rm -f "$hyprland_config_tmp"' EXIT

{
    cat << 'HYPRLUA'
-- Managed by arch-setup for Hyprland 0.55+.

------------------
---- MONITORS ----
------------------

HYPRLUA

    build_hypr_monitor_lua

    cat << 'HYPRLUA'
---------------------
---- MY PROGRAMS ----
---------------------

local terminal = "ghostty"
local fileManager = "dolphin"
local menu = "rofi -show drun"
local home = os.getenv("HOME") or "."
local screenshots = home .. "/Pictures/screenshots"
local wallpaper = home .. "/Pictures/wallpaper2.png"

local function shell_quote(value)
    return string.format("%q", value)
end

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("test -f " .. shell_quote(wallpaper) .. " && hyprpaper")
end)

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in = 3,
        gaps_out = 5,
        border_size = 0,
        col = {
            active_border = {
                colors = { "rgba(33ccffee)", "rgba(00ff99ee)" },
                angle = 45,
            },
            inactive_border = "rgba(595959aa)",
        },
        resize_on_border = false,
        allow_tearing = false,
        layout = "dwindle",
    },

    decoration = {
        rounding = 10,
        rounding_power = 2,
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        shadow = {
            enabled = true,
            range = 4,
            render_power = 3,
            color = 0xee1a1a1a,
        },
        blur = {
            enabled = true,
            size = 3,
            passes = 1,
            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
    },
})

hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1}, {0.32, 1} } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
hl.curve("linear",         { type = "bezier", points = { {0, 0}, {1, 1} } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5}, {0.75, 1} } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0}, {0.1, 1} } })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 7,    bezier = "quick" })

---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout = "us,ru",
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        kb_rules = "",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            natural_scroll = true,
        },
    },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

hl.device({
    name = "epic-mouse-v1",
    sensitivity = -0.5,
})

---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER"

hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind("ALT + TAB", hl.dsp.window.cycle_next())
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("hyprctl switchxkblayout current next"))
hl.bind(mainMod .. " + PRINT", hl.dsp.exec_cmd("mkdir -p " .. shell_quote(screenshots) .. " && hyprshot -m region -o " .. shell_quote(screenshots)))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("uwsm stop"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "l" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "r" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "u" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "d" }))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }))
end

hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
HYPRLUA
} > "$hyprland_config_tmp"

if ! hypr_verify_output="$(Hyprland --verify-config -c "$hyprland_config_tmp" 2>&1)"; then
    printf '%s\n' "$hypr_verify_output" >&2
    error "Generated Hyprland Lua config failed validation; existing config was preserved."
fi

mv "$hyprland_config_tmp" "$hyprland_config"
trap - EXIT
info "Hyprland Lua config validated successfully."

if [[ -f "$HOME/.config/hypr/hyprland.conf" ]]; then
    warn "Legacy hyprland.conf was backed up and left in place; Hyprland 0.55+ uses hyprland.lua by default."
fi

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
