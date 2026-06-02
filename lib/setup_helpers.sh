#!/bin/bash

# --- UI Helpers ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

function info() { echo -e "${BLUE}info:${NC} $1" >&2; }
function success() { echo -e "${GREEN}✓${NC} $1" >&2; }
function warn() {
    if [ "$1" = "-n" ]; then
        shift
        echo -en "${YELLOW}$*${NC}" >&2
    else
        echo -e "${YELLOW}$*${NC}" >&2
    fi
}
function error() { echo -e "${RED}error:${NC} $1" >&2; }
function task() { echo -ne "  ${BLUE}..${NC} $1... " >&2; }
function section() { echo -e "\n${BOLD}${BLUE}==>${NC} ${BOLD}$1${NC}" >&2; }
function step() { section "$1"; }
function print_OK() { echo -e "${GREEN}OK${NC}" >&2; }
function print_failed() { echo -e "${RED}FAILED${NC}" >&2; }

function summary() {
    local label=$1
    local value=$2
    local note=$3
    printf "  %-18s: ${BOLD}%s${NC} %s\n" "$label" "$value" "$note"
}

# --- Complex Logic Helpers ---

function probe_network_interface() {
    local default_fallback="${1:-eth0}"
    local iface
    iface=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -n1)
    echo "${iface:-$default_fallback}"
}

function check_audio_daemons() {
    local mode="${1:-auto-stop}"
    local core_daemons=(mpd upmpdcli raspotify)
    local active_daemons=()

    task "Checking for active audio daemons"
    for svc in "${core_daemons[@]}"; do
        if systemctl is-active --quiet "$svc"; then
            active_daemons+=("$svc")
        fi
    done

    if [ "${#active_daemons[@]}" -eq 0 ]; then
        print_OK
    else
        warn "Detected running daemons: ${active_daemons[*]}"
        case "$mode" in
            auto-stop)
                warn "Stopping active daemons before setup for deterministic probing..."
                local stop_failed=()
                for svc in "${active_daemons[@]}"; do
                    if ! systemctl stop "$svc" >/dev/null 2>&1; then
                        stop_failed+=("$svc")
                    fi
                done
                if [ "${#stop_failed[@]}" -gt 0 ]; then
                    print_failed
                    error "Failed stopping daemon(s): ${stop_failed[*]}"
                    exit 1
                fi
                print_OK
                ;;
            fail-fast)
                print_failed
                error "Active daemons detected (${active_daemons[*]}). Re-run with VOX_DAEMON_PRECHECK_MODE=auto-stop to allow controlled stop."
                exit 1
                ;;
            off)
                warn "Skipping daemon precheck action (VOX_DAEMON_PRECHECK_MODE=off)."
                print_OK
                ;;
            *)
                print_failed
                error "Unsupported daemon precheck mode: '$mode'"
                exit 1
                ;;
        esac
    fi
}

function probe_alsa_device() {
    local policy="${1:-direct-first}"
    local probe_file="/tmp/vox-alsa-probe.raw"
    local selected_device="default"

    task "Selecting ALSA playback device for MPD"
    if ! command -v aplay >/dev/null 2>&1; then
        warn "aplay not available. Falling back to default."
        echo "default"
        return
    fi

    if ! dd if=/dev/zero of="$probe_file" bs=1764 count=50 status=none; then
        warn "Could not create ALSA probe sample. Falling back to default."
        echo "default"
        return
    fi

    local card_name
    card_name=$(aplay -l 2>/dev/null | awk -F'[: ]+' '/^card [0-9]+:/{print $3; exit}')
    
    local candidates=()
    if [ -n "$card_name" ]; then
        if [ "$policy" = "direct-first" ]; then
            candidates+=("hw:CARD=${card_name},DEV=0" "plughw:CARD=${card_name},DEV=0" "sysdefault:CARD=${card_name}")
        else
            candidates+=("plughw:CARD=${card_name},DEV=0" "hw:CARD=${card_name},DEV=0" "sysdefault:CARD=${card_name}")
        fi
    fi
    candidates+=("hw:0,0" "default")

    # Deduplicate
    local unique=()
    for c in "${candidates[@]}"; do
        local skip=0
        for e in "${unique[@]}"; do [[ "$c" == "$e" ]] && skip=1 && break; done
        [[ $skip -eq 0 ]] && unique+=("$c")
    done

    for c in "${unique[@]}"; do
        if timeout 4 aplay -q -D "$c" -f S16_LE -r 44100 -c 2 "$probe_file" >/dev/null 2>&1; then
            selected_device="$c"
            break
        fi
    done

    rm -f "$probe_file"
    
    if [ "$selected_device" = "default" ]; then
        warn "No preferred ALSA PCM candidate validated. Using default PCM."
    fi
    print_OK
    echo "$selected_device"
}

function authorize_tidal() {
    local cred_file="$1"
    local cred_dir
    cred_dir=$(dirname "$cred_file")

    info "Starting interactive Tidal authorization..."
    mkdir -p "$cred_dir"
    chown upmpdcli:upmpdcli "$cred_dir"

    if ! sudo -u upmpdcli python3 /usr/share/upmpdcli/cdplugins/tidal/get_credentials.py -t pkce -f "$cred_file"; then
        warn "Tidal authorization skipped or failed."
        return 1
    fi
    return 0
}

run_cmd() {
    if "$@"; then
        print_OK
    else
        print_failed
        exit 1
    fi
}

run_optional() {
    if "$@"; then
        print_OK
    else
        warn "SKIPPED"
        warn "Non-fatal command failed: $*"
    fi
}

run_block() {
    if bash -e -o pipefail -c "$1"; then
        print_OK
    else
        print_failed
        exit 1
    fi
}