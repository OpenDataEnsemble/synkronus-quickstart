#!/bin/bash
# Paste this whole file into the "User data" / "Cloud config" box when you create
# a new Ubuntu 24.04 server (DigitalOcean, Hetzner, Vultr, Linode, AWS, ...).
# The server installs Synkronus by itself on first boot. No terminal needed.
#
# 1. Change the password on the next line (letters and numbers are safest).
export SYNK_ADMIN_PASSWORD="change-me-to-a-long-password"
# 2. Optional: your own domain, already pointing to the server's IP. Leave empty
#    to get a free address: https://<server-ip>.sslip.io
export SYNK_DOMAIN=""
# 3. Create the server, wait about 5-10 minutes, then open the address above and
#    log in as "admin" with your password.
curl -fsSL https://raw.githubusercontent.com/OpenDataEnsemble/synkronus-quickstart/main/get.sh | bash -s -- --yes > /var/log/synkronus-install.log 2>&1
