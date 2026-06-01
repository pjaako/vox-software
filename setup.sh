#!/bin/bash
# Vox Bootstrap Script
# Formalizing the "Snowflake" into a "Recipe"

set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HELPERS_FILE="$SCRIPT_DIR/lib/setup_helpers.sh"
if [ ! -f "$HELPERS_FILE" ]; then
    echo "error: missing helper file: $HELPERS_FILE" >&2
    exit 1
fi
source "$HELPERS_FILE"

echo -e "${BOLD}--- Starting Vox Setup ---${NC}"

task "Checking audio hardware"
if [ ! -d /dev/snd ]; then
    warn "NOT FOUND"
    warn "/dev/snd not found! Audio hardware may not be accessible."
else
    print_OK
fi

task "Checking for active audio daemons"
DAEMON_PRECHECK_MODE="${VOX_DAEMON_PRECHECK_MODE:-auto-stop}"
CORE_DAEMONS=(mpd upmpdcli raspotify)
ACTIVE_DAEMONS=()

for svc in "${CORE_DAEMONS[@]}"; do
    if systemctl is-active --quiet "$svc"; then
        ACTIVE_DAEMONS+=("$svc")
    fi
done

if [ "${#ACTIVE_DAEMONS[@]}" -eq 0 ]; then
    print_OK
else
    warn "Detected running daemons: ${ACTIVE_DAEMONS[*]}"
    case "$DAEMON_PRECHECK_MODE" in
        auto-stop)
            warn "Stopping active daemons before setup for deterministic probing..."
            STOP_FAILED=()
            for svc in "${ACTIVE_DAEMONS[@]}"; do
                if ! systemctl stop "$svc" >/dev/null 2>&1; then
                    STOP_FAILED+=("$svc")
                fi
            done
            if [ "${#STOP_FAILED[@]}" -gt 0 ]; then
                print_failed
                error "Failed stopping daemon(s): ${STOP_FAILED[*]}"
                exit 1
            fi
            print_OK
            ;;
        fail-fast)
            print_failed
            error "Active daemons detected (${ACTIVE_DAEMONS[*]}). Re-run with VOX_DAEMON_PRECHECK_MODE=auto-stop to allow controlled stop."
            exit 1
            ;;
        off)
            warn "Skipping daemon precheck action (VOX_DAEMON_PRECHECK_MODE=off)."
            print_OK
            ;;
        *)
            print_failed
            error "Unsupported VOX_DAEMON_PRECHECK_MODE='${DAEMON_PRECHECK_MODE}'. Use: auto-stop, fail-fast, or off."
            exit 1
            ;;
    esac
fi
info "Daemon precheck mode: ${DAEMON_PRECHECK_MODE}"


section "Installing basic tools"
task "Updating apt repositories"
run_cmd apt-get update -qq

task "Installing curl, gpg, gnupg2"
run_cmd apt-get install -y -qq --no-install-recommends curl gpg gnupg2


section "Adding external repositories"

task "Configuring Raspotify repository"
run_block 'curl -fsSL https://dtcooper.github.io/raspotify/key.asc | gpg --batch --yes --dearmor -o /usr/share/keyrings/raspotify_key.asc 2>/dev/null
echo "deb [signed-by=/usr/share/keyrings/raspotify_key.asc] https://dtcooper.github.io/raspotify raspotify main" > /etc/apt/sources.list.d/raspotify.list'

task "Configuring upmpdcli repository"
run_block "curl -fsSL https://www.lesbonscomptes.com/pages/lesbonscomptes.gpg | gpg --batch --yes --dearmor -o /usr/share/keyrings/lesbonscomptes.gpg 2>/dev/null
cat <<'EOF' > /etc/apt/sources.list.d/upmpdcli.sources
Types: deb deb-src
URIs: http://www.lesbonscomptes.com/upmpdcli/downloads/debian/
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/lesbonscomptes.gpg
EOF"


section "Installing core audio packages"
task "Creating raspotify user"
useradd -r -s /usr/sbin/nologin -G audio raspotify 2>/dev/null || true
print_OK

task "Refreshing package lists"
run_cmd apt-get update -qq

task "Installing MPD, upmpdcli, Raspotify and dependencies"
run_cmd apt-get install -y -qq --no-install-recommends \
    mpd mpc alsa-utils \
    upmpdcli upmpdcli-radio-paradise upmpdcli-radios upmpdcli-tidal \
    raspotify \
    python3-pip python3-venv \
    glow bat


section "Installing Tidal integration"
task "Creating Python Virtual Environment"
run_cmd python3 -m venv /var/cache/upmpdcli/venv

task "Installing Tidal API Python module into venv"
run_cmd /var/cache/upmpdcli/venv/bin/pip install -q --upgrade tidalapi


section "Applying service configurations"

task "Selecting ALSA playback device for MPD"
MPD_ALSA_DEVICE="default"
ALSA_SELECTOR_POLICY="${ALSA_SELECTOR_POLICY:-direct-first}"
PROBE_FILE="/tmp/vox-alsa-probe.raw"

if command -v aplay >/dev/null 2>&1; then
    if dd if=/dev/zero of="$PROBE_FILE" bs=1764 count=50 status=none; then
        ALSA_CARD_NAME=$(aplay -l 2>/dev/null | awk -F'[: ]+' '/^card [0-9]+:/{print $3; exit}')
        CANDIDATES=()

        if [ -n "$ALSA_CARD_NAME" ]; then
            if [ "$ALSA_SELECTOR_POLICY" = "direct-first" ]; then
                CANDIDATES+=("hw:CARD=${ALSA_CARD_NAME},DEV=0" "plughw:CARD=${ALSA_CARD_NAME},DEV=0" "sysdefault:CARD=${ALSA_CARD_NAME}")
            else
                CANDIDATES+=("plughw:CARD=${ALSA_CARD_NAME},DEV=0" "hw:CARD=${ALSA_CARD_NAME},DEV=0" "sysdefault:CARD=${ALSA_CARD_NAME}")
            fi
        fi

        CANDIDATES+=("hw:0,0" "default")

        UNIQUE_CANDIDATES=()
        for candidate in "${CANDIDATES[@]}"; do
            skip="0"
            for existing in "${UNIQUE_CANDIDATES[@]}"; do
                if [ "$candidate" = "$existing" ]; then
                    skip="1"
                    break
                fi
            done
            if [ "$skip" = "0" ]; then
                UNIQUE_CANDIDATES+=("$candidate")
            fi
        done

        for candidate in "${UNIQUE_CANDIDATES[@]}"; do
            if timeout 4 aplay -q -D "$candidate" -f S16_LE -r 44100 -c 2 "$PROBE_FILE" >/dev/null 2>&1; then
                MPD_ALSA_DEVICE="$candidate"
                break
            fi
        done

        rm -f "$PROBE_FILE"
    else
        warn "Could not create ALSA probe sample. Falling back to default."
    fi
else
    warn "aplay not available. Falling back to default."
fi

if [ "$MPD_ALSA_DEVICE" = "default" ]; then
    warn "No preferred ALSA PCM candidate validated. Using default PCM."
fi
print_OK
info "MPD ALSA device selected: ${MPD_ALSA_DEVICE} (policy: ${ALSA_SELECTOR_POLICY})"

task "Configuring MPD"
cat <<EOF > /etc/mpd.conf
music_directory		"/var/lib/mpd/music"
playlist_directory		"/var/lib/mpd/playlists"
db_file			"/var/lib/mpd/tag_cache"
state_file			"/var/lib/mpd/state"
sticker_file                   "/var/lib/mpd/sticker.sql"
user				"mpd"
bind_to_address			"localhost"
zeroconf_enabled		"no"
input {
        plugin "curl"
}
filesystem_charset		"UTF-8"
audio_output {
	type		"alsa"
	name		"Audio Output"
	device		"${MPD_ALSA_DEVICE}"
	mixer_type      "software"
}
EOF
print_OK

# upmpdcli
# We use a heredoc but keep existing credentials if possible.
info "Configuring upmpdcli..."
EXISTING_TIDAL_USER=$(grep "^tidaluser =" /etc/upmpdcli.conf 2>/dev/null | cut -d'=' -f2 | xargs || true)
if [ -t 0 ]; then
    warn -n "${BOLD}??${NC} Enter Tidal user email [${EXISTING_TIDAL_USER:-your-email@example.com}]: "
    read NEW_TIDAL_USER
    TIDAL_USER=${NEW_TIDAL_USER:-$EXISTING_TIDAL_USER}
else
    TIDAL_USER=$EXISTING_TIDAL_USER
fi
TIDAL_USER=${TIDAL_USER:-"your-email@example.com"}

if [ "$TIDAL_USER" != "your-email@example.com" ]; then
    warn "\n---------------------------------------------"
    warn "${BOLD}IMPORTANT: Tidal OAuth2 Authorization Required"
    echo -e "To complete Tidal setup, you will need to authorize this device:"
    echo -e "1. After this script finishes, check the service logs:"
    echo -e "   ${BOLD}journalctl -u upmpdcli -f${NC}"
    echo -e "2. Look for a link like: ${BLUE}https://link.tidal.com/ABCDE${NC}"
    echo -e "3. Open that link in your browser and log in to Tidal to approve."
    warn "---------------------------------------------\n"
fi

task "Writing upmpdcli configuration"
cat <<EOF > /etc/upmpdcli.conf
upnpiface = eth0
upnpav = 0
openhome = 1
ohmodelname = ProxVox-ONKYO
ohproductname = ProxVox-ONKYO
msfriendlyname = ProxVox-Tidal-Gateway
webserverdocumentroot = /var/cache/upmpdcli/www
uprcluser = bugsbunny
uprcltitle = Local Music
upradiosuser = bugsbunny
upradiostitle = Upmpdcli Radio List
radio-paradiseuser = bugsbunny
radio-paradisetitle = Radio Paradise
bbctitle = BBC Sounds
friendlyname = ProxVox-ONKYO (Tidal/OpenHome)
tidaluser = $TIDAL_USER
tidalautostart = 1
EOF
print_OK

task "Applying systemd override for Python venv and user"
mkdir -p /etc/systemd/system/upmpdcli.service.d
cat <<EOF > /etc/systemd/system/upmpdcli.service.d/venv_path.conf
[Service]
User=upmpdcli
Group=upmpdcli
AmbientCapabilities=CAP_NET_BIND_SERVICE
Environment=PATH=/var/cache/upmpdcli/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF
print_OK

task "Applying systemd override for Raspotify hardening"
mkdir -p /etc/systemd/system/raspotify.service.d
cat <<EOF > /etc/systemd/system/raspotify.service.d/hardening.conf
[Service]
User=raspotify
Group=raspotify
SupplementaryGroups=audio
PrivateUsers=no
EOF
print_OK

task "Configuring Raspotify"
cat <<EOF > /etc/raspotify/conf
LIBRESPOT_BITRATE=320
LIBRESPOT_NAME="ProxVox-ONKYO (Spotify Connect)"
LIBRESPOT_QUIET=
TMPDIR=/tmp
EOF
print_OK


section "Initializing hardware mixer levels"
task "Unmuting and setting Master/PCM/Front to 100%"
run_block 'amixer sset Master 100% unmute >/dev/null 2>&1
amixer sset PCM 100% >/dev/null 2>&1
amixer sset Front 100% unmute >/dev/null 2>&1'


section "Starting services"
task "Reloading systemd"
run_cmd systemctl daemon-reload

task "Enabling and restarting core services"
systemctl enable mpd upmpdcli raspotify >/dev/null 2>&1
run_cmd systemctl restart mpd upmpdcli raspotify


section "Cleaning up"
task "Removing temporary files"
run_cmd apt-get clean

echo -e "\n${BOLD}${GREEN}--- Vox Setup Complete! ---${NC}"
