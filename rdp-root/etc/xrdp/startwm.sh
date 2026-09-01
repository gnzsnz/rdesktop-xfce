#!/bin/bash
# Replaces the Debian-supplied startwm.sh. The stock version execs
# /etc/X11/Xsession, whose dispatcher scripts assume a logind/systemd
# session is being tracked. Per xrdp upstream's own guidance for
# non-systemd environments, we bypass that dispatcher and start the
# desktop directly:
# https://github.com/neutrinolabs/xrdp/discussions/2309
#   ("xrdp doesn't understand dbus or systemd at all - it just runs
#    the startwm.sh script... you may be best off replacing it with
#    something which just starts the desktop of your choice.")
# Truncated (not appended) on every new session start, and under /config
# (not /tmp) so it's inspectable from the host without a docker exec and
# survives container restarts.
exec >"/config/.startwm.$(id -u).log" 2>&1
set -x

# No systemd/pam_systemd here to create /run/user/<uid>; init-xrdp-user.sh
# pre-creates it as root before this script ever runs.
XDG_RUNTIME_DIR="/run/user/$(id -u)"
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    echo "WARNING: $XDG_RUNTIME_DIR missing -- init-xrdp-user.sh should" \
         "have created this at container boot. Continuing anyway; dbus" \
         "and some XFCE components may misbehave." >&2
fi
export XDG_RUNTIME_DIR

[ -r /etc/profile ] && . /etc/profile
[ -r "$HOME/.profile" ] && . "$HOME/.profile"

exec dbus-launch --exit-with-session startxfce4
