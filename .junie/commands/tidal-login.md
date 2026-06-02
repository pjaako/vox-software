---
description: Run the interactive Tidal login process
---

Please help the user authorize Tidal. 

1. If this is a fresh installation, instruct the user to run the master setup script:
   `sudo bash setup.sh`
2. If the user needs to re-authorize or change accounts, they can run the official Tidal login script directly:
   `sudo -u upmpdcli python3 /usr/share/upmpdcli/cdplugins/tidal/get_credentials.py -t pkce -f /var/cache/upmpdcli/tidal/pkce.credentials.json`
3. Explain the steps:
   - Open the provided Tidal link in their browser.
   - Log in and approve.
   - Copy the URL of the resulting page (even if it shows an error) and paste it back into the terminal.
4. After successful authorization, they must restart the service:
   `sudo systemctl restart upmpdcli`
