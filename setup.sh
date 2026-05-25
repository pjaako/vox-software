#!/bin/bash
# Vox Bootstrap Script
# Formalizing the "Snowflake" into a "Recipe"

set -e

echo "--- Starting Vox Setup ---"

# 0. Hardware Check
if [ ! -d /dev/snd ]; then
    echo "WARNING: /dev/snd not found! Audio hardware may not be accessible."
fi

# 1. Basic Tools
apt-get update
apt-get install -y curl gpg gnupg2

# 2. Add Repositories and Keys
echo "Adding repository keys..."

# Raspotify
curl -fsSL https://dtcooper.github.io/raspotify/key.asc | gpg --dearmor -o /usr/share/keyrings/raspotify_key.asc
echo "deb [signed-by=/usr/share/keyrings/raspotify_key.asc] https://dtcooper.github.io/raspotify raspotify main" > /etc/apt/sources.list.d/raspotify.list

# upmpdcli
curl -fsSL https://www.lesbonscomptes.com/pages/lesbonscomptes.gpg | gpg --dearmor -o /usr/share/keyrings/lesbonscomptes.gpg
cat <<EOF > /etc/apt/sources.list.d/upmpdcli.sources
Types: deb deb-src
URIs: http://www.lesbonscomptes.com/upmpdcli/downloads/debian/
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/lesbonscomptes.gpg
EOF

# 3. Install Packages
apt-get update
apt-get install -y \
    mpd mpc \
    upmpdcli upmpdcli-radio-paradise upmpdcli-radios \
    raspotify \
    glow bat

# 4. Apply Configurations
echo "Applying service configurations..."

# MPD
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

# upmpdcli
# We use a heredoc but keep existing credentials if possible.
echo "Configuring upmpdcli..."
EXISTING_TIDAL_USER=$(grep "^tidaluser =" /etc/upmpdcli.conf 2>/dev/null | cut -d'=' -f2 | xargs || true)
if [ -t 0 ]; then
    read -p "Enter Tidal user email [${EXISTING_TIDAL_USER:-your-email@example.com}]: " NEW_TIDAL_USER
    TIDAL_USER=${NEW_TIDAL_USER:-$EXISTING_TIDAL_USER}
else
    TIDAL_USER=$EXISTING_TIDAL_USER
fi
TIDAL_USER=${TIDAL_USER:-"your-email@example.com"}

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

# Raspotify
cat <<EOF > /etc/raspotify/conf
LIBRESPOT_BITRATE=320
LIBRESPOT_NAME="ProxVox-ONKYO (Spotify Connect)"
LIBRESPOT_QUIET=
TMPDIR=/tmp
EOF

# 7. Restart Services
systemctl daemon-reload
systemctl restart mpd upmpdcli raspotify

echo "--- Vox Setup Complete! ---"
