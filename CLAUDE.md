# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

Vox is a declarative Bash bootstrap for a headless hi-fi audio stack running in a Debian 13 (Trixie) LXC container. There are no build steps, tests, or package manifests — the entire system state is expressed as a single idempotent script.

## Running the Setup

```bash
# Full deployment (requires root inside the LXC)
sudo bash setup.sh

# Dry-run: discovers config (network interface, ALSA device) without applying anything
sudo bash setup.sh --check
```

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `VOX_INTERFACE` | auto-probed | Network interface for UPnP announcements |
| `VOX_DAEMON_PRECHECK_MODE` | `auto-stop` | How to handle running daemons before setup: `auto-stop`, `fail-fast`, `off` |
| `ALSA_SELECTOR_POLICY` | `direct-first` | ALSA candidate order: `direct-first` prefers `hw:` over `plughw:`, any other value reverses this |

## Architecture

**`setup.sh`** is the source of truth. It:
1. Sources `lib/setup_helpers.sh` for all shared logic
2. Auto-probes the network interface and ALSA device
3. Installs packages from the Raspotify and lesbonscomptes (upmpdcli) external APT repos
4. Writes config file heredocs to `/etc/mpd.conf`, `/etc/upmpdcli.conf`, `/etc/raspotify/conf`
5. Applies systemd drop-in overrides under `/etc/systemd/system/*.service.d/`
6. Runs interactive Tidal PKCE auth via the upmpdcli venv Python

**`lib/setup_helpers.sh`** contains all reusable logic:
- UI primitives: `task`, `section`, `info`, `warn`, `error`, `print_OK`, `print_failed`, `summary`
- Command runners: `run_cmd` (fatal on failure), `run_optional` (non-fatal), `run_block` (runs a string via `bash -e -o pipefail`)
- `probe_network_interface` — reads the default route via `ip route`
- `probe_alsa_device` — generates a short raw PCM sample and tries `aplay` against each candidate device; returns the first that succeeds
- `check_audio_daemons` — stops/blocks/ignores running mpd/upmpdcli/raspotify depending on `VOX_DAEMON_PRECHECK_MODE`
- `authorize_tidal` — runs `get_credentials.py` as the `upmpdcli` user using the venv Python

## Deployed Services

| Service | Config file | Restart |
|---|---|---|
| MPD | `/etc/mpd.conf` | `systemctl restart mpd` |
| upmpdcli | `/etc/upmpdcli.conf` | `systemctl restart upmpdcli` |
| raspotify | `/etc/raspotify/conf` | `systemctl restart raspotify` |

Tidal credentials live at `/var/cache/upmpdcli/tidal/pkce.credentials.json`, owned by the `upmpdcli` user. The tidalapi Python module is installed into `/var/cache/upmpdcli/venv/`.

## The Recipe Rule

If you change any config that `setup.sh` writes (e.g., `/etc/mpd.conf`, `/etc/upmpdcli.conf`), you **must** update the corresponding heredoc in `setup.sh` — never make standalone manual edits. The script is designed to be re-run on a fresh container to reproduce the full stack.

## Key Design Constraints

- **Exclusive audio access:** Concurrent playback from multiple sources is intentionally unsupported. Only one service holds the ALSA device at a time.
- **No audio mixing:** Tidal and Spotify sharing output simultaneously is treated as an anti-pattern.
- **Future DSP:** CamillaDSP is the designated engine for any future EQ/room-correction needs (not yet implemented).
- **Discuss before committing:** Proposed changes must be discussed with the user and explicitly approved before any git commit.

## Useful Diagnostics

```bash
systemctl status mpd upmpdcli raspotify
journalctl -u upmpdcli -f   # Tidal auth and plugin handshakes
journalctl -u mpd -f
mpc status
aplay -l                    # List detected ALSA cards/devices
```
