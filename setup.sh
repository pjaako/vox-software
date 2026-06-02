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

# --- Discovery & Configuration ---

# Argument Parsing
CHECK_MODE=0
for arg in "$@"; do
    case $arg in
        -c|--check) CHECK_MODE=1 ;;
    esac
done

# 1. Network Interface Discovery
PROBED_IFACE=$(probe_network_interface "")
VOX_INTERFACE="${VOX_INTERFACE:-${PROBED_IFACE:-eth0}}"

# 2. Discovery Summary
echo -e "${BOLD}--- Starting Vox Setup ---${NC}"

section "Configuration Discovery"
summary "Network Interface" "$VOX_INTERFACE" "$([ -n "$PROBED_IFACE" ] && [ "$VOX_INTERFACE" = "$PROBED_IFACE" ] && echo "(Auto-probed)" || echo "(Manual/Fallback)")"

if [ "$CHECK_MODE" -eq 1 ]; then
    echo ""
    info "Dry-run mode active (--check). Exiting without changes."
    exit 0
fi

task "Checking audio hardware"
if [ ! -d /dev/snd ]; then
    warn "NOT FOUND"
    warn "/dev/snd not found! Audio hardware may not be accessible."
else
    print_OK
fi

check_audio_daemons "${VOX_DAEMON_PRECHECK_MODE:-auto-stop}"


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

MPD_ALSA_DEVICE=$(probe_alsa_device "${ALSA_SELECTOR_POLICY:-direct-first}")
info "MPD ALSA device selected: ${MPD_ALSA_DEVICE} (policy: ${ALSA_SELECTOR_POLICY:-direct-first})"

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

task "Writing upmpdcli configuration"
cat <<EOF > /etc/upmpdcli.conf
upnpiface = $VOX_INTERFACE
upnpav = 0
openhome = 1
ohmodelname = ProxVox-ONKYO
ohproductname = ProxVox-ONKYO
msfriendlyname = ProxVox-Tidal-Gateway
webserverdocumentroot = /var/cache/upmpdcli/www

# Service Activation (Bogus user variables as per manual)
uprcluser = uprcl
upradiosuser = upradio
radio-paradiseuser = radio-paradise
tidaluser = tidal
qobuzuser = qobuz
highresaudiouser = highresaudio

# Autostart flags
uprclautostart = 1
tidalautostart = 1

uprcltitle = Local Music
upradiostitle = Internet Radio
radio-paradisetitle = Radio Paradise
bbctitle = BBC Sounds
friendlyname = ProxVox-ONKYO (Tidal/OpenHome)
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

section "Account Configuration"
authorize_tidal "/var/cache/upmpdcli/tidal/pkce.credentials.json"

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
info "Infrastructure is ready."
