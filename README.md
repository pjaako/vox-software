# Vox: The Audio Engine of [ProxVox](https://github.com/pjaako/ProxVox)¹

Vox-software is a headless software infrastructure declaration designed for hi-fi playback and streaming integration. It serves as the "audio engine" for the **[ProxVox](https://github.com/pjaako/ProxVox)¹** project.

Built on **Debian 13 (Trixie)** and optimized for **LXC containers**, Vox provides a reproducible way to manage an audio stack supporting, among other services, Tidal and Spotify audio endpoint.

---

## Features

- **Multi-Source Playback:** Integrated support for Tidal (via [upmpdcli](https://framagit.org/medoc92/upmpdcli)), Internet Radios, and Spotify Connect ([raspotify](https://github.com/dtcooper/raspotify)).
- **Network Rendering:** Fully compatible UPnP/DLNA/OpenHome renderer.
- **High-Fidelity Audio:** Headless design with ALSA passthrough for bit-perfect potential.
- **Reproducible State:** "Nuke and Pave" readiness—deployment and configuration are handled by a single master script.

---

## Architecture: The "Why"

Unlike traditional "snowflake" audio setups, Vox is built with **agency and tinkering** in mind:

*   **LXC over Docker:** Chosen for stable hardware passthrough and persistent system-level debugging.
*   **Debian Trixie (13):** Provides up-to-date repositories for `upmpdcli` and other audio services.
*   **Declarative Setup:** All configurations are defined in `setup.sh`. Manual edits are discouraged in favor of updating the "recipe."

---

## Getting Started

### 1. Host Preparation
Before running the setup, ensure your LXC host (e.g., Proxmox) is configured for hardware passthrough.

**Proxmox VE Requirements:**
1. Enable **Nesting** and **Keyctl** in the LXC options.
2. Edit `/etc/pve/lxc/ID.conf` on the host and add native device passthrough entries.
   Find your audio devices on the host with `ls -l /dev/snd`, then add entries for each (e.g., control, pcm, timer):
   ```text
   dev0: /dev/snd/controlC0,gid=29
   dev1: /dev/snd/pcmC0D0p,gid=29
   dev2: /dev/snd/timer,gid=29
   ```
   *Note: `gid=29` corresponds to the 'audio' group. This ensures the container has the correct permissions to access the hardware.*

### 2. Installation
Run the master bootstrap script inside your fresh Debian 13 LXC:

```bash
git clone https://github.com/pjaako/vox-software.git
cd vox-software
sudo bash setup.sh
```

---

## Core Components

| Component | Role | Control Command |
| :--- | :--- | :--- |
| **MPD** | The decoding engine | `systemctl restart mpd` |
| **upmpdcli** | UPnP/Tidal/Radio Paradise bridge | `systemctl restart upmpdcli` |
| **raspotify** | Spotify Connect bridge | `systemctl restart raspotify` |
| **MPC** | Lightweight CLI remote | `mpc status` |

---

## Maintenance & Health

### ALSA Output Selection Policy

`setup.sh` now probes ALSA playback candidates before writing `/etc/mpd.conf`.

- Daemon preflight is run near startup to make reruns predictable when services are already active.
- Default precheck mode is `auto-stop` via `VOX_DAEMON_PRECHECK_MODE` (`auto-stop` | `fail-fast` | `off`).
- Core daemons covered by preflight: `mpd`, `upmpdcli`, and `raspotify`.

- Default policy is `direct-first` (can be overridden with `ALSA_SELECTOR_POLICY`).
- Candidate order for `direct-first`: `hw:CARD=<name>,DEV=0` -> `plughw:CARD=<name>,DEV=0` -> `sysdefault:CARD=<name>` -> `hw:0,0` -> `default`.
- Candidate order for resilience mode (any value other than `direct-first`): `plughw` first, then `hw`, then the same fallbacks.
- Probing uses a finite raw sample with `aplay` to avoid false negatives caused by timeout-killing infinite streams.
- The first working candidate is written into the MPD heredoc as `device "${MPD_ALSA_DEVICE}"`.

**Check all services:**
```bash
systemctl status mpd upmpdcli raspotify
```

**Monitor Live Logs:**
- `journalctl -u upmpdcli -f` (Best for Tidal debugging)
- `journalctl -u mpd -f`

**Common Tasks:**
- **Update Database:** `mpc update`
- **Tidal Config:** Edit `/etc/upmpdcli.conf` then `systemctl restart upmpdcli`.

---

## Agent Support

This repository includes configuration for automation and maintenance agents:
- **Project Guidelines:** See [AGENTS.md](./AGENTS.md).
- **Subagents:** Specialized handlers are available for audio debugging.
- **Custom Commands:** Shortcuts for soundchecks and logs are defined in `.junie/commands/`.

---

## Governance
- **Source of Truth:** [setup.sh](./setup.sh)
- **Helper Library:** [lib/setup_helpers.sh](./lib/setup_helpers.sh) (loaded by `setup.sh` for shared UI and command-runner functions)
- **Guidelines:** [AGENTS.md](./AGENTS.md)

---

Coauthored by Junie

¹ *Not affiliated, sponsored, or endorsed by [Proxmox Server Solutions GmbH](https://www.proxmox.com).*
