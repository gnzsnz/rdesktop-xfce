#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# Sets the RDP login password for the desktop user. Runs once per
# container start (oneshot), before xrdp-sesman comes up.
#
#   RDP_PASSWORD      - set explicitly to pin the password (recommended for
#                       anything but throwaway/local use)
#   RDP_PASSWORD_FILE - read RDP_PASSWORD from a file instead (Docker/Swarm
#                       secrets, etc). Exclusive with RDP_PASSWORD.
#   RDP_USER          - defaults to "abc", the LinuxServer baseimage user
#
# If neither RDP_PASSWORD nor RDP_PASSWORD_FILE is set, a random password
# is generated once and persisted under /config so it survives container
# recreation, and is printed to the container log exactly once.
set -euo pipefail

RDP_USER="${RDP_USER:-abc}"
CRED_FILE="/config/.rdp_credentials"

if ! id "$RDP_USER" >/dev/null 2>&1; then
	echo "[init-xrdp-user] user '$RDP_USER' does not exist yet -- baseimage-ubuntu's" >&2
	echo "[init-xrdp-user] own PUID/PGID init should have created it. Skipping." >&2
	exit 0
fi

if [ -n "${RDP_PASSWORD:-}" ] && [ -n "${RDP_PASSWORD_FILE:-}" ]; then
	echo "[init-xrdp-user] error: both RDP_PASSWORD and RDP_PASSWORD_FILE are set (but are exclusive)" >&2
	exit 1
fi

if [ -n "${RDP_PASSWORD:-}" ]; then
	PASSWORD="$RDP_PASSWORD"
elif [ -n "${RDP_PASSWORD_FILE:-}" ] && [ -s "${RDP_PASSWORD_FILE}" ]; then
	PASSWORD="$(cat "${RDP_PASSWORD_FILE}")"
elif [ -s "$CRED_FILE" ]; then
	PASSWORD="$(cat "$CRED_FILE")"
else
	# `|| true`: `head -c20` closing its read end early sends `tr` a
	# SIGPIPE; under `pipefail` that makes this whole statement's exit
	# status 141, which `set -e` then treats as fatal even though $PASSWORD
	# was assigned correctly. Confirmed live: a genuinely fresh boot (no
	# RDP_PASSWORD, no persisted credentials file) crashed this oneshot
	# with exactly that signal before this fix.
	PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)" || true
	mkdir -p /config
	printf '%s' "$PASSWORD" >"$CRED_FILE"
	chmod 600 "$CRED_FILE"
	chown "$RDP_USER" "$CRED_FILE" 2>/dev/null || true
	echo "###########################################################"
	echo "# Generated RDP password for user '${RDP_USER}':"
	echo "# ${PASSWORD}"
	echo "# Persisted at ${CRED_FILE} -- set RDP_PASSWORD to override."
	echo "###########################################################"
fi

echo "${RDP_USER}:${PASSWORD}" | chpasswd

RDP_UID="$(id -u "$RDP_USER")"
RDP_GID="$(id -g "$RDP_USER")"
mkdir -p "/run/user/${RDP_UID}"
chown "${RDP_UID}:${RDP_GID}" "/run/user/${RDP_UID}"
chmod 0700 "/run/user/${RDP_UID}"

# /var/run/xrdp: the xrdp package's own postinst doesn't set group
# ownership/setgid bits on this, unlike LinuxServer's rdesktop-family
# images (confirmed against their init-prep-xrdp) which explicitly give
# the xrdp group write access via setgid/sticky bits. Mirror that here --
# but only the top-level dir: confirmed live that xrdp-sesman itself
# deletes and recreates "sockdir" (root:root, defaults) on every one of
# its own startups, so setting perms on sockdir here would just be
# silently clobbered a moment later and isn't worth the dead code.
mkdir -p /var/run/xrdp
chown root:xrdp /var/run/xrdp
chmod 2775 /var/run/xrdp

# Self-signed TLS cert/key, generated once per deployment and persisted
# under /config (not baked into the image layer). Confirmed live: the
# package-postinst-generated /etc/xrdp/cert.pem is a symlink to the
# system snakeoil cert, identical byte-for-byte across every container
# started from the same image tag -- every deployment sharing one image
# version would share one private key. Gate/layout matches webtop's own
# init-nginx cert step (docker-baseimage-selkies) exactly, so a /config
# volume carried over from webtop already has a working cert/key here and
# this step just reuses it instead of generating a second one.
if [ ! -f "/config/ssl/cert.pem" ]; then
	mkdir -p /config/ssl
	openssl req -new -x509 \
		-days 3650 -nodes \
		-out /config/ssl/cert.pem \
		-keyout /config/ssl/cert.key \
		-subj "/C=US/ST=CA/L=Carlsbad/O=Linuxserver.io/OU=LSIO Server/CN=*"
	chmod 600 /config/ssl/cert.key
	chown -R "$RDP_USER" /config/ssl
fi
