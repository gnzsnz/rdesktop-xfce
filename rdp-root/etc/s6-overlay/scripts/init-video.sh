#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# Grants abc access to any /dev/dri (and /dev/dvb) render/video device
# nodes present at container start, by GID -- mirrors LinuxServer's own
# webtop init-video (docker-baseimage-selkies), trimmed of its GLX/NVIDIA
# passthrough logic (irrelevant to xrdp, which never does GLX passthrough).
# No-op if no such devices are mapped in (today's default xrdp-only case).
set -uo pipefail

FILES=$(find /dev/dri /dev/dvb -type c -print 2>/dev/null)

for i in $FILES; do
	DEV_GID=$(stat -c '%g' "${i}")
	if id -G abc | grep -qw "${DEV_GID}" && [ "$(stat -c '%A' "${i}" | cut -b 5,6)" = "rw" ]; then
		echo "[init-video] ${i}: permissions already OK"
		continue
	fi
	if ! id -G abc | grep -qw "${DEV_GID}"; then
		GROUP_NAME=$(getent group "${DEV_GID}" | cut -d: -f1)
		if [ -z "${GROUP_NAME}" ]; then
			GROUP_NAME="dri$(head /dev/urandom | tr -dc 'a-z0-9' | head -c4)"
			groupadd "${GROUP_NAME}"
			groupmod -g "${DEV_GID}" "${GROUP_NAME}"
			echo "[init-video] created group ${GROUP_NAME} (gid ${DEV_GID})"
		fi
		usermod -aG "${GROUP_NAME}" abc
		echo "[init-video] added abc to ${GROUP_NAME} (gid ${DEV_GID}) for ${i}"
	fi
	if [ "$(stat -c '%A' "${i}" | cut -b 5,6)" != "rw" ]; then
		chmod g+rw "${i}"
	fi
done
