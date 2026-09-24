#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# The firefox-profile named volume (docker-compose.yml, mounted over
# ~/.config/mozilla/firefox) is created fresh by Docker, owned root:root --
# Firefox can't write its profile there until chowned once. Runs every
# boot; chown is idempotent so re-running on an already-fixed profile is a
# no-op.
set -euo pipefail

RDP_USER="${RDP_USER:-abc}"
PROFILE_DIR="/config/.config/mozilla/firefox"

if [ -d "$PROFILE_DIR" ]; then
	chown -R "$RDP_USER:$RDP_USER" "$PROFILE_DIR"
	echo "> Firefox fix >> set permissions."
fi
