#!/bin/bash
# Vox Bootstrap Script
# Formalizing the "Snowflake" into a "Recipe"

set -e

# --- UI Helpers ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

function info() { echo -e "${BLUE}info:${NC} $1"; }
function success() { echo -e "${GREEN}✓${NC} $1"; }
function warn() {
    if [ "$1" = "-n" ]; then
        shift
        echo -en "${YELLOW}$*${NC}"
    else
        echo -e "${YELLOW}$*${NC}"
    fi
}
function error() { echo -e "${RED}error:${NC} $1"; }
function task() { echo -ne "  ${BLUE}..${NC} $1... "; }
function step() { echo -e "\n${BOLD}${BLUE}==>${NC} ${BOLD}$1${NC}"; }
function print_OK() { echo -e "${GREEN}OK${NC}"; }
function print_failed() { echo -e "${RED}FAILED${NC}"; }

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

echo -e "${BOLD}--- Starting Vox Setup ---${NC}"

# 0. Hardware Check
task "Checking audio hardware"
if [ ! -d /dev/snd ]; then
    warn "NOT FOUND"
    warn "/dev/snd not found! Audio hardware may not be accessible."
else
    print_OK
fi

# 1. Basic Tools
step "Installing basic tools"
task "Updating apt repositories"
run_cmd apt-get update -qq

task "Installing curl, gpg, gnupg2"
run_cmd apt-get install -y -qq --no-install-recommends curl gpg gnupg2

# 2. Add Repositories and Keys
step "Adding external repositories"

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

# 3. Install Packages
step "Installing core audio packages"
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

# 4. Install Tidal API
step "Installing Tidal integration"
task "Creating Python Virtual Environment"
run_cmd python3 -m venv /var/cache/upmpdcli/venv

task "Installing Tidal API Python module into venv"
run_cmd /var/cache/upmpdcli/venv/bin/pip install -q --upgrade tidalapi

# 5. Apply Configurations
step "Applying service configurations"

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
	device		"hw:0,0"
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

# 6. Hardware Mixer
step "Initializing hardware mixer levels"
task "Unmuting and setting Master/PCM/Front to 100%"
run_block 'amixer sset Master 100% unmute >/dev/null 2>&1
amixer sset PCM 100% >/dev/null 2>&1
amixer sset Front 100% unmute >/dev/null 2>&1'

# 7. Restart Services
step "Starting services"
task "Reloading systemd"
run_cmd systemctl daemon-reload

task "Enabling and restarting core services"
systemctl enable mpd upmpdcli raspotify >/dev/null 2>&1
run_cmd systemctl restart mpd upmpdcli raspotify

# 8. Cleanup
step "Cleaning up"
task "Removing temporary files"
run_cmd apt-get clean

echo -e "\n${BOLD}${GREEN}--- Vox Setup Complete! ---${NC}"
