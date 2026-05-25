# Vox: The Audio Engine of [ProxVox]https://github.com/pjaako/ProxVox*

Vox-software is a headless software infrastructure declaration designed for hi-fi playback and streaming integration. It serves as the "audio engine" for the **[ProxVox*]https://github.com/pjaako/ProxVox** project.

Built on **Debian 13 (Trixie)** and optimized for **LXC containers**, Vox provides a reproducible way to manage an audio stack supporting, among other services, Tidal and Spotify audio endpoint.

---

## Features

- **Multi-Source Playback:** Integrated support for Tidal (via [upmpdcli]https://framagit.org/medoc92/upmpdcli), Internet Radios, and Spotify Connect ([raspotify]https://github.com/dtcooper/raspotify).
- **Network Rendering:** Fully compatible UPnP/DLNA/OpenHome renderer.
- **High-Fidelity Audio:** Headless design with ALSA passthrough for bit-perfect potential.
- **Reproducible State:** "Nuke and Pave" readiness—deployment and configuration are handled by a single master script.

---

## Architecture: The "Why"

Unlike traditional "monolithic" audio setups, Vox is built with **agency and tinkering** in mind:

*   **LXC over Docker:** Chosen for stable hardware passthrough and persistent system-level debugging.
*   **Debian Trixie (13):** Provides up-to-date repositories for `upmpdcli` and other audio services.
*   **Declarative Setup:** All configurations are defined in `setup.sh`. Manual edits are discouraged in favor of updating the "recipe."

---

## Getting Started

### 1. Host Preparation
Before running the setup, ensure your LXC host (e.g., Proxmox) is configured for hardware passthrough.

**Proxmox VE Requirements:**
1. Enable **Nesting** and **Keyctl** in the LXC options.
2. Edit `/etc/pve/lxc/ID.conf` on the host and add:
   ```text
   lxc.cgroup2.devices.allow: c 116:* rwm
   lxc.mount.entry: /dev/snd dev/snd none bind,optional,create=dir
   ```

### 2. Installation
Run the master bootstrap script inside your fresh Debian 13 LXC:

```bash
git clone https://github.com/your-username/vox.git
cd vox
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
- **Custom Commands:** Shortcuts for health checks and logs are defined in `.junie/commands/`.

---

## Governance
- **Source of Truth:** [setup.sh](./setup.sh)
- **Guidelines:** [AGENTS.md](./AGENTS.md)

---

Coauthored by Junie
****Not affiliated, sponsored, or endorsed by [Proxmox](https://github.com/proxmox).*** 
