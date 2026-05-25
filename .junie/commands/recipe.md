---
description: Apply or update the setup.sh recipe to ensure system state consistency
---

Please execute the `/root/setup.sh` script to ensure the system is in its declarative state. 
Before running it, verify if any manual changes were made to `/etc/mpd.conf` or `/etc/upmpdcli.conf` that are NOT yet captured in the `setup.sh` heredocs. 
If there are discrepancies, update `setup.sh` first to respect the "Recipe Rule".
