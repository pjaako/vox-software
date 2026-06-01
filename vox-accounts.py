import os
import sys
import subprocess

CONF_FILE = "/etc/upmpdcli.conf"

def print_header():
    print("\033[1;34m==>\033[0m \033[1mVox Account Configuration\033[0m")
    print("    This utility helps you link your music services.\n")

def get_input(prompt, default):
    try:
        val = input(f"  {prompt} [{default}]: ").strip()
        return val if val else default
    except EOFError:
        return default

def update_conf(key, value):
    try:
        if not os.path.exists(CONF_FILE):
            with open(CONF_FILE, 'w') as f:
                f.write(f"{key} = {value}\n")
            return

        with open(CONF_FILE, 'r') as f:
            lines = f.readlines()
        
        new_lines = []
        found = False
        for line in lines:
            if line.startswith(f"{key} ="):
                new_lines.append(f"{key} = {value}\n")
                found = True
            else:
                new_lines.append(line)
        
        if not found:
            new_lines.append(f"{key} = {value}\n")
            
        with open(CONF_FILE, 'w') as f:
            f.writelines(new_lines)
    except Exception as e:
        print(f"Error updating config: {e}")
        sys.exit(1)

def main():
    if os.geteuid() != 0:
        print("Error: This script must be run as root (to update /etc/upmpdcli.conf)")
        sys.exit(1)

    print_header()
    
    # Read existing
    existing_user = "your-email@example.com"
    existing_media_user = os.getlogin() if sys.stdin.isatty() else "vox-user"
    
    if os.path.exists(CONF_FILE):
        with open(CONF_FILE, 'r') as f:
            for line in f:
                if line.startswith("tidaluser ="):
                    existing_user = line.split("=")[1].strip()
                if line.startswith("uprcluser ="):
                    existing_media_user = line.split("=")[1].strip()

    new_media_user = get_input("Media Display Name/User", existing_media_user)
    new_tidal_user = get_input("Tidal Email Account", existing_user)

    print("\n  Saving configuration...")
    update_conf("uprcluser", new_media_user)
    update_conf("upradiosuser", new_media_user)
    update_conf("radio-paradiseuser", new_media_user)
    update_conf("tidaluser", new_tidal_user)
    
    print("  Restarting upmpdcli...")
    subprocess.run(["systemctl", "restart", "upmpdcli"], check=False)

    if new_tidal_user != "your-email@example.com":
        instructions = f"""
# Tidal Authorization Guide

To complete your Tidal setup, you must authorize this device:

1. **Watch the logs**:
   Run `journalctl -u upmpdcli -f` in another terminal.

2. **Find the link**:
   Look for a line like: `https://link.tidal.com/ABCDE`

3. **Approve**:
   Open the link in your browser, log in, and click **Finish**.

*Once authorized, your music will be available via any UPnP/OpenHome controller.*
"""
        md_path = "/tmp/vox-tidal-auth.md"
        with open(md_path, "w") as f:
            f.write(instructions)
        
        # Try to use glow for beautiful output
        try:
            subprocess.run(["glow", md_path])
        except FileNotFoundError:
            # Fallback to plain print if glow not found
            print(instructions)
        finally:
            if os.path.exists(md_path):
                os.remove(md_path)

if __name__ == "__main__":
    main()
