#!/usr/bin/env bash
# ============================================================================
# select-mirror.sh -- Detect and apply the fastest Arch mirror for this region
# ============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
header(){ echo -e "\n${CYAN}==============================================================${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}==============================================================${NC}\n"; }

MIRRORLIST_PATH="/etc/pacman.d/mirrorlist"
DEFAULT_TOP_N=5
COUNTRY=""
TOP_N="$DEFAULT_TOP_N"
MAX_CANDIDATES=0
DRY_RUN=0
LIST_COUNTRIES=0
SUDO_CMD=""

TEMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

usage() {
    cat << 'EOF'
Usage:
  ./select-mirror.sh                      Auto-detect country, keep top 5 mirrors
  ./select-mirror.sh -c US               Force country
  ./select-mirror.sh -n 10               Keep top 10 mirrors
  ./select-mirror.sh --dry-run           Benchmark + print, no file writes
  ./select-mirror.sh --max-candidates 20 Cap mirrors to test
  ./select-mirror.sh --list-countries    Show valid country codes
  ./select-mirror.sh -h                  Show help
EOF
}

is_positive_int() {
    [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

is_non_negative_int() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

is_valid_country_code() {
    [[ "${1:-}" =~ ^[A-Z]{2}$ ]]
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--country)
                [[ $# -ge 2 ]] || error "Missing value for $1"
                COUNTRY="$(echo "$2" | tr '[:lower:]' '[:upper:]')"
                if [[ "$COUNTRY" != "ALL" ]] && ! is_valid_country_code "$COUNTRY"; then
                    error "Invalid country code: $2 (expected ISO 2-letter code, e.g. US)"
                fi
                [[ "$COUNTRY" == "ALL" ]] && COUNTRY="all"
                shift 2
                ;;
            -n)
                [[ $# -ge 2 ]] || error "Missing value for -n"
                is_positive_int "$2" || error "Invalid -n value: $2 (must be >= 1)"
                TOP_N="$2"
                shift 2
                ;;
            --max-candidates)
                [[ $# -ge 2 ]] || error "Missing value for --max-candidates"
                is_non_negative_int "$2" || error "Invalid --max-candidates value: $2 (must be >= 0)"
                MAX_CANDIDATES="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --list-countries)
                LIST_COUNTRIES=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown argument: $1 (use -h for help)"
                ;;
        esac
    done
}

require_commands() {
    local cmd
    for cmd in curl awk sed grep sort head mktemp date tr; do
        command -v "$cmd" >/dev/null 2>&1 || error "Required command not found: $cmd"
    done
}

ensure_privileges() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        return
    fi

    if [[ ! -f "$MIRRORLIST_PATH" ]]; then
        error "Mirrorlist not found: $MIRRORLIST_PATH"
    fi

    if [[ "$EUID" -eq 0 ]]; then
        SUDO_CMD=""
        return
    fi

    command -v sudo >/dev/null 2>&1 || error "sudo is required in apply mode."
    if ! sudo -n true 2>/dev/null; then
        info "Sudo authentication is required for mirrorlist update."
        sudo -v || error "sudo authentication failed."
    fi
    SUDO_CMD="sudo"
}

list_country_codes() {
    local json
    json="$(curl -fsSL --connect-timeout 5 --max-time 20 "https://archlinux.org/mirrors/status/json/")" \
        || error "Failed to fetch country list from Arch mirror status."

    info "Available country codes:"
    echo "$json" \
        | grep -oE '"country_code"[[:space:]]*:[[:space:]]*"[A-Z]{2}"' \
        | sed -E 's/.*"([A-Z]{2})"/\1/' \
        | sort -u \
        | awk '{printf "%s%s", (NR==1?"":" "), $0} END{print ""}'
}

detect_country() {
    local detected=""

    detected="$(curl -fsSL --connect-timeout 5 --max-time 8 "https://ipinfo.io/json" 2>/dev/null \
        | sed -n 's/.*"country"[[:space:]]*:[[:space:]]*"\([A-Za-z][A-Za-z]\)".*/\1/p' \
        | head -n 1 \
        | tr '[:lower:]' '[:upper:]' || true)"

    if ! is_valid_country_code "$detected"; then
        detected="$(curl -fsSL --connect-timeout 5 --max-time 8 "https://ifconfig.co/json" 2>/dev/null \
            | sed -n 's/.*"country_iso"[[:space:]]*:[[:space:]]*"\([A-Za-z][A-Za-z]\)".*/\1/p' \
            | head -n 1 \
            | tr '[:lower:]' '[:upper:]' || true)"
    fi

    if is_valid_country_code "$detected"; then
        echo "$detected"
    else
        echo "all"
    fi
}

fetch_mirror_candidates() {
    local country="$1"
    local out_file="$2"
    local url
    local raw_file="$TEMP_DIR/mirrors.raw"

    if [[ "$country" == "all" ]]; then
        url="https://archlinux.org/mirrorlist/?protocol=https&ip_version=4&use_mirror_status=on"
    else
        url="https://archlinux.org/mirrorlist/?country=${country}&protocol=https&ip_version=4&use_mirror_status=on"
    fi

    curl -fsSL --connect-timeout 5 --max-time 20 "$url" > "$raw_file" || return 1

    sed -n -e 's/^#Server = //p' -e 's/^Server = //p' "$raw_file" \
        | awk 'NF && !seen[$0]++' > "$out_file"
}

cap_candidates_if_needed() {
    local in_file="$1"
    local out_file="$2"

    if [[ "$MAX_CANDIDATES" -gt 0 ]]; then
        head -n "$MAX_CANDIDATES" "$in_file" > "$out_file"
    else
        cp "$in_file" "$out_file"
    fi
}

benchmark_mirrors() {
    local mirrors_file="$1"
    local results_file="$2"

    local mirror test_url elapsed
    local tested=0
    local successful=0
    local failed=0

    : > "$results_file"

    while IFS= read -r mirror; do
        [[ -n "$mirror" ]] || continue
        tested=$((tested + 1))

        test_url="${mirror//\$repo\/os\/\$arch/extra/os/x86_64/extra.db}"
        if [[ "$test_url" == "$mirror" ]]; then
            test_url="${mirror%/}/extra/os/x86_64/extra.db"
        fi

        if elapsed="$(curl -fsSL -o /dev/null --connect-timeout 5 --max-time 10 -w '%{time_total}' "$test_url" 2>/dev/null)"; then
            successful=$((successful + 1))
            printf '%s|%s\n' "$elapsed" "$mirror" >> "$results_file"
        else
            failed=$((failed + 1))
        fi
    done < "$mirrors_file"

    sort -n -t'|' -k1,1 "$results_file" -o "$results_file"

    echo "$tested|$successful|$failed"
}

print_summary() {
    local results_file="$1"
    local tested="$2"
    local successful="$3"
    local failed="$4"
    local selected_n="$5"

    header "Mirror Benchmark Summary"
    info "Mirrors tested: $tested"
    info "Successful: $successful"
    info "Failed/timeout: $failed"
    info "Selected top: $selected_n"

    awk -F'|' -v limit="$selected_n" 'NR<=limit {printf "  %2d. %s s  %s\n", NR, $1, $2}' "$results_file"
}

apply_mirrorlist() {
    local results_file="$1"
    local selected_n="$2"
    local selected_country="$3"

    local timestamp backup_path output_file
    timestamp="$(date +%Y%m%d%H%M%S)"
    backup_path="${MIRRORLIST_PATH}.bak.${timestamp}"
    output_file="$TEMP_DIR/mirrorlist.new"

    {
        echo "## Generated by select-mirror.sh on $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        if [[ "$selected_country" == "all" ]]; then
            echo "## Country filter: worldwide"
        else
            echo "## Country filter: $selected_country"
        fi
        echo ""
        awk -F'|' -v limit="$selected_n" 'NR<=limit {print "Server = " $2}' "$results_file"
    } > "$output_file"

    if [[ -n "$SUDO_CMD" ]]; then
        sudo cp -a "$MIRRORLIST_PATH" "$backup_path"
        sudo mv "$output_file" "$MIRRORLIST_PATH"
    else
        cp -a "$MIRRORLIST_PATH" "$backup_path"
        mv "$output_file" "$MIRRORLIST_PATH"
    fi

    info "Mirrorlist backup: $backup_path"
}

sync_databases() {
    info "Refreshing pacman databases with selected mirrors..."
    if [[ -n "$SUDO_CMD" ]]; then
        sudo pacman -Syy
    else
        pacman -Syy
    fi
}

main() {
    local detected_country selected_country
    local country_candidates="$TEMP_DIR/candidates.country"
    local all_candidates="$TEMP_DIR/candidates.all"
    local final_candidates="$TEMP_DIR/candidates.final"
    local benchmark_results="$TEMP_DIR/benchmark.results"
    local stats tested successful failed selected_n

    parse_args "$@"
    require_commands

    if [[ "$LIST_COUNTRIES" -eq 1 ]]; then
        list_country_codes
        exit 0
    fi

    ensure_privileges

    if [[ -n "$COUNTRY" ]]; then
        selected_country="$COUNTRY"
        info "Using user-provided country: $selected_country"
    else
        detected_country="$(detect_country)"
        selected_country="$detected_country"
        if [[ "$selected_country" == "all" ]]; then
            warn "Country auto-detection failed. Falling back to worldwide mirrors."
        else
            info "Detected country: $selected_country"
        fi
    fi

    info "Fetching mirror candidates..."
    if ! fetch_mirror_candidates "$selected_country" "$country_candidates"; then
        warn "Failed to fetch country-specific mirrors."
        selected_country="all"
    fi

    if [[ "$selected_country" != "all" ]] && [[ ! -s "$country_candidates" ]]; then
        warn "No mirrors found for $selected_country. Falling back to worldwide mirrors."
        selected_country="all"
    fi

    if [[ "$selected_country" == "all" ]]; then
        fetch_mirror_candidates "all" "$all_candidates" \
            || error "Failed to fetch worldwide mirror list."
        [[ -s "$all_candidates" ]] || error "Worldwide mirror list is empty."
        cap_candidates_if_needed "$all_candidates" "$final_candidates"
    else
        cap_candidates_if_needed "$country_candidates" "$final_candidates"
    fi

    if [[ ! -s "$final_candidates" ]]; then
        error "No mirror candidates available for benchmarking."
    fi

    info "Benchmarking mirrors..."
    stats="$(benchmark_mirrors "$final_candidates" "$benchmark_results")"
    tested="${stats%%|*}"
    stats="${stats#*|}"
    successful="${stats%%|*}"
    failed="${stats##*|}"

    if [[ "$successful" -eq 0 ]]; then
        error "All mirrors failed benchmarking. Original mirrorlist preserved."
    fi

    selected_n="$TOP_N"
    if [[ "$successful" -lt "$selected_n" ]]; then
        warn "Only $successful mirrors were reachable; selecting those."
        selected_n="$successful"
    fi

    print_summary "$benchmark_results" "$tested" "$successful" "$failed" "$selected_n"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "Dry-run mode: mirrorlist was not modified."
        exit 0
    fi

    apply_mirrorlist "$benchmark_results" "$selected_n" "$selected_country"
    sync_databases
    info "Mirror selection and refresh complete."
}

main "$@"
