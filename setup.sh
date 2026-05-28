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
function warn() { echo -e "${YELLOW}warning:${NC} $1"; }
function error() { echo -e "${RED}error:${NC} $1"; }
function task() { echo -ne "  ${BLUE}..${NC} $1... "; }
function step() { echo -e "\n${BOLD}${BLUE}==>${NC} ${BOLD}$1${NC}"; }

echo -e "${BOLD}--- Starting Vox Setup ---${NC}"

# 0. Hardware Check
task "Checking audio hardware"
if [ ! -d /dev/snd ]; then
    echo -e "${YELLOW}NOT FOUND${NC}"
    warn "/dev/snd not found! Audio hardware may not be accessible."
else
    echo -e "${GREEN}OK${NC}"
fi

# 1. Basic Tools
step "Installing basic tools"
task "Updating apt repositories"
apt-get update -qq && echo -e "${GREEN}DONE${NC}" || (echo -e "${RED}FAILED${NC}"; exit 1)

task "Installing curl, gpg, gnupg2"
apt-get install -y -qq --no-install-recommends curl gpg gnupg2 && echo -e "${GREEN}DONE${NC}" || (echo -e "${RED}FAILED${NC}"; exit 1)

# 2. Add Repositories and Keys
step "Adding external repositories"

task "Configuring Raspotify repository"
curl -fsSL https://dtcooper.github.io/raspotify/key.asc | gpg --dearmor -o /usr/share/keyrings/raspotify_key.asc 2>/dev/null
echo "deb [signed-by=/usr/share/keyrings/raspotify_key.asc] https://dtcooper.github.io/raspotify raspotify main" > /etc/apt/sources.list.d/raspotify.list
echo -e "${GREEN}DONE${NC}"

task "Configuring upmpdcli repository"
curl -fsSL https://www.lesbonscomptes.com/pages/lesbonscomptes.gpg | gpg --dearmor -o /usr/share/keyrings/lesbonscomptes.gpg 2>/dev/null
cat <<EOF > /etc/apt/sources.list.d/upmpdcli.sources
Types: deb deb-src
URIs: http://www.lesbonscomptes.com/upmpdcli/downloads/debian/
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/lesbonscomptes.gpg
EOF
echo -e "${GREEN}DONE${NC}"

# 3. Install Packages
step "Installing core audio packages"
task "Refreshing package lists"
apt-get update -qq && echo -e "${GREEN}DONE${NC}" || (echo -e "${RED}FAILED${NC}"; exit 1)

task "Installing MPD, upmpdcli, Raspotify and dependencies"
apt-get install -y -qq --no-install-recommends \
    mpd mpc alsa-utils \
    upmpdcli upmpdcli-radio-paradise upmpdcli-radios upmpdcli-tidal \
    raspotify \
    python3-pip \
    glow bat && echo -e "${GREEN}DONE${NC}" || (echo -e "${RED}FAILED${NC}"; exit 1)

# 4. Install Tidal API
step "Installing Tidal integration"
task "Installing Tidal API Python module"
pip3 install -q --break-system-packages tidalapi && echo -e "${GREEN}DONE${NC}" || (echo -e "${RED}FAILED${NC}"; exit 1)

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
echo -e "${GREEN}DONE${NC}"

# upmpdcli
# We use a heredoc but keep existing credentials if possible.
info "Configuring upmpdcli..."
EXISTING_TIDAL_USER=$(grep "^tidaluser =" /etc/upmpdcli.conf 2>/dev/null | cut -d'=' -f2 | xargs || true)
if [ -t 0 ]; then
    echo -en "${YELLOW}${BOLD}??${NC} Enter Tidal user email [${EXISTING_TIDAL_USER:-your-email@example.com}]: "
    read NEW_TIDAL_USER
    TIDAL_USER=${NEW_TIDAL_USER:-$EXISTING_TIDAL_USER}
else
    TIDAL_USER=$EXISTING_TIDAL_USER
fi
TIDAL_USER=${TIDAL_USER:-"your-email@example.com"}

if [ "$TIDAL_USER" != "your-email@example.com" ]; then
    echo -e "\n${YELLOW}---------------------------------------------${NC}"
    echo -e "${YELLOW}${BOLD}IMPORTANT: Tidal OAuth2 Authorization Required${NC}"
    echo -e "To complete Tidal setup, you will need to authorize this device:"
    echo -e "1. After this script finishes, check the service logs:"
    echo -e "   ${BOLD}journalctl -u upmpdcli -f${NC}"
    echo -e "2. Look for a link like: ${BLUE}https://link.tidal.com/ABCDE${NC}"
    echo -e "3. Open that link in your browser and log in to Tidal to approve."
    echo -e "${YELLOW}---------------------------------------------${NC}\n"
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
echo -e "${GREEN}DONE${NC}"

task "Configuring Raspotify"
cat <<EOF > /etc/raspotify/conf
LIBRESPOT_BITRATE=320
LIBRESPOT_NAME="ProxVox-ONKYO (Spotify Connect)"
LIBRESPOT_QUIET=
TMPDIR=/tmp
EOF
echo -e "${GREEN}DONE${NC}"

# 6. Hardware Mixer
step "Initializing hardware mixer levels"
task "Unmuting and setting Master/PCM/Front to 100%"
amixer sset Master 100% unmute >/dev/null 2>&1
amixer sset PCM 100% >/dev/null 2>&1
amixer sset Front 100% unmute >/dev/null 2>&1
echo -e "${GREEN}DONE${NC}"

# 7. Restart Services
step "Starting services"
task "Reloading systemd"
systemctl daemon-reload && echo -e "${GREEN}DONE${NC}"

task "Enabling and restarting core services"
systemctl enable mpd upmpdcli raspotify >/dev/null 2>&1
systemctl restart mpd upmpdcli raspotify && echo -e "${GREEN}DONE${NC}"

# 8. Cleanup
step "Cleaning up"
task "Removing temporary files"
apt-get clean && echo -e "${GREEN}DONE${NC}"

echo -e "\n${BOLD}${GREEN}--- Vox Setup Complete! ---${NC}"
