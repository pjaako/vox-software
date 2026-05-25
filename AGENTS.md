### Vox: Agent Guidelines & Architecture

This document serves as the "Instruction Manual" for future AI agents or system administrators managing this Vox LXC setup. It captures the architectural "Why" behind the "How."
Vox is the audio-focused component of the **ProxVox** project (the other part being "Prox" for NAS, QEMU, and other services).

---

#### 1. Project Goals
- **High-Quality Audio:** Headless playback with flexible output options.
- **Agency & Tinkering:** All configurations must be transparent, visible, and reproducible.
- **Declarative State:** Use `setup.sh` to apply changes rather than manual imperative edits.

#### 2. Architectural Choices (The "Why")
- **LXC vs. Docker:** LXC was chosen for stable hardware passthrough and persistent system-level debugging.
- **Debian Trixie (13):** Provides up-to-date repositories for `upmpdcli` and other audio services.

#### 3. Reference Solutions
When stuck or looking for feature inspiration, peek at:
- **DietPi:** For optimized Debian-based service configurations.
- **Volumio/Moode:** For UI patterns and advanced MPD plugin integration.
- **upmpdcli.org:** For the latest on Tidal/Qobuz/Radio Paradise bridge capabilities.

#### 4. Mandatory Best Practices
- **Device Awareness:** Verify audio device availability before troubleshooting services.
- **The "Recipe" Rule:** If you modify a configuration file (e.g., `/etc/mpd.conf`), you **MUST** update the corresponding heredoc in `setup.sh`.
- **Log Monitoring:** Use `journalctl -u upmpdcli -f` to verify Tidal authentication and plugin handshakes.
- **LXC Host Prep:** Ensure hardware passthrough and container options (Nesting, Keyctl) are configured on the host before deployment (see [Section 7](#7-host-side-preparation)).

#### 5. Anti-Patterns (Things to Avoid)
- **The Snowflake Trap:** Making manual changes that aren't documented or scripted.
- **Root-Only Execution:** Never run the media services as `root` (except where required for initial binding).
- **Silent Failures:** Always check service exit codes after a configuration reload.

#### 6. Workflow Capture (Commands & Subagents)
- **Custom Commands:** Use `.junie/commands/` to define shortcuts for repetitive human tasks (e.g., `/health`, `/logs`).
- **Subagents:** Use `.junie/agents/` to define specialized handlers for complex delegation (e.g., `audio-troubleshooter`).
- **Standardization:** All operational logic must be captured in either a script, a command, or a subagent to ensure it remains part of the project's "living" documentation.

#### 7. Host-Side Preparation
Before running `setup.sh` inside the LXC, the host must be prepared to allow hardware access.

##### 7.1 Generic Linux (LXC/LXD)
If using LXD, run the following command to pass through audio devices:
```bash
lxc config device add <container_name> audio unix-char path=/dev/snd
```
For raw LXC, add these lines to your container configuration file:
```text
lxc.cgroup2.devices.allow: c 116:* rwm
lxc.mount.entry: /dev/snd dev/snd none bind,optional,create=dir
```

##### 7.2 Proxmox VE
1. **Options:** Under the "Options" tab in the Proxmox web UI for the LXC:
   - Enable **Nesting**.
   - Enable **Keyctl**.
2. **Manual Config:** Edit the config file on the Proxmox host: `/etc/pve/lxc/ID.conf` (replace `ID` with your container ID).
   - Add the following lines to the end of the file:
     ```text
     lxc.cgroup2.devices.allow: c 116:* rwm
     lxc.mount.entry: /dev/snd dev/snd none bind,optional,create=dir
     ```
   - *Note:* `116` is the standard major number for audio devices. Verify on host with `ls -l /dev/snd`.
3. **Restart:** Reboot the LXC to apply hardware passthrough changes.

---

#### 8. The Master Command: `setup.sh`
The `./setup.sh` script is the definitive source of truth.
- **Execution:** `bash setup.sh`
- **Function:** Rebuilds repositories, installs packages, applies systemd overrides, and sets baseline configs.
- **Nuke and Pave:** This system is designed to be fully reproducible on a fresh Debian 13 LXC by running this script.
