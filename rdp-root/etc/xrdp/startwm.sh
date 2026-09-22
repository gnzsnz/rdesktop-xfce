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

# pipewire/pipewire-pulse/wireplumber ship only systemd --user units (no
# xdg-autostart fallback) -- with no systemd --user instance here, nothing
# else will ever start them. Hand-start them in their own private D-Bus
# session, isolated from xfce4-session's own bus below.
#
# Confirmed live, in this order:
#  1. Starting them with no bus at all makes wireplumber's dbus module
#     autolaunch a bus of its own, keyed off the X11 display -- this
#     raced xfce4-session's own dbus-launch and killed the session's bus
#     ~4s in (xfce4-session SIGABRT; xrdp-sesman.log: "Window manager
#     exited quickly").
#  2. Sharing one bus between this block and xfce4-session (exporting
#     DBUS_SESSION_BUS_ADDRESS before `exec dbus-launch ...startxfce4`)
#     avoided the race but didn't fix it: the shared bus itself died
#     ~20s into the session (GLib "DBus connection closed" across every
#     XFCE component at once), taking xfce4-session down with it the
#     same way. Cause not fully root-caused; not worth it when a private
#     bus sidesteps the whole class of failure.
# So: a dedicated dbus-daemon for pipewire/wireplumber only, with
# DISPLAY/XAUTHORITY unset for the `dbus-launch` call so it can't read or
# write the X11 autolaunch property and end up reused by xfce4-session's
# own dbus-launch moments later. Runs in a subshell so none of this
# leaks into the env `exec startxfce4` inherits.
#
# `pgrep` guard: on session reconnect, startwm.sh runs again while the
# previous pipewire/wireplumber/dbus-daemon trio (orphaned under PID 1,
# never torn down between sessions) is still alive -- skip re-spawning a
# second stack on top of it.
if command -v pipewire >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x pipewire >/dev/null 2>&1; then
	(
		unset DISPLAY XAUTHORITY
		eval "$(dbus-launch --sh-syntax)"
		export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
		pipewire &
		sleep 1
		wireplumber &
		pipewire-pulse &
		sleep 1
	)
fi

# pipewire-xrdp.desktop (installed by the pipewire-module-xrdp package
# under /etc/xdg/autostart) is picked up by xfce4-session on its own and
# only loads the xrdp-sink/xrdp-source module into the pipewire server
# started above -- it does not start the server itself.
exec dbus-launch --exit-with-session startxfce4
