# syntax=docker/dockerfile:1
#
# TWS / IB Gateway RDP desktop image, on LinuxServer's Ubuntu base
# (s6-overlay v3, no systemd)
# xrdp + xorgxrdp + XFCE run as native s6-rc services.
#
# See:
# https://github.com/linuxserver/docker-baseimage-ubuntu/releases
#
ARG BASE_IMAGE=lscr.io/linuxserver/baseimage-ubuntu:resolute
# BASE_IMAGE is tagged via the ARG default above
# hadolint ignore=DL3006
FROM ${BASE_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive

# hadolint ignore=DL3008,DL4006,SC3040
RUN <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "**** Mozilla APT repo (Firefox) ****"
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl sudo
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg \
  -o /etc/apt/keyrings/packages.mozilla.org.asc
printf 'Types: deb\nURIs: https://packages.mozilla.org/apt\nSuites: mozilla\nComponents: main\nSigned-By: /etc/apt/keyrings/packages.mozilla.org.asc\n' \
  > /etc/apt/sources.list.d/mozilla.sources
printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n\nPackage: firefox\nPin: release o=Ubuntu\nPin-Priority: -1\n' \
  > /etc/apt/preferences.d/mozilla

echo "**** desktop + xrdp stack ****"
apt-get update
apt-get upgrade -y
apt-get install -y --no-install-recommends \
  xfce4-session xfwm4 xfce4-panel xfce4-settings xfdesktop4 libxfce4ui-utils \
  xfce4-cpugraph-plugin xfce4-netload-plugin xfce4-taskmanager xfce4-xkb-plugin \
  xfce4-notes gvfs gvfs-backends gvfs-fuse xfce4-terminal thunar dbus dbus-x11 xfconf \
  xfce4-appfinder xrdp xorgxrdp xauth firefox mousepad xfce4-pulseaudio-plugin \
  pipewire pipewire-pulse wireplumber pipewire-module-xrdp pulseaudio-utils \
  x11-xserver-utils fonts-noto-core fonts-liberation tumbler
rm -rf /var/lib/apt/lists/*

echo "**** xrdp/sesman config ****"
# certificate=/key_file=: point at /config so the TLS cert is generated
# once per deployment (init-xrdp-user.sh) instead of sharing the
# postinst-baked one across every container from this image tag.
# EnableUserWindowManager=false: always use our startwm.sh, never a
# per-user ~/startwm.sh.
sed -i \
  -e 's/^security_layer=.*/security_layer=tls/' \
  -e 's/^crypt_level=.*/crypt_level=high/' \
  -e 's|^certificate=.*|certificate=/config/ssl/cert.pem|' \
  -e 's|^key_file=.*|key_file=/config/ssl/cert.key|' \
  /etc/xrdp/xrdp.ini
sed -i \
  -e 's/^EnableUserWindowManager=.*/EnableUserWindowManager=false/' \
  /etc/xrdp/sesman.ini

echo "**** xorgxrdp glamor/DRI3 on AMD/NVIDIA ****"
# xorgxrdp's stock xorg.conf allow-lists only the i915 and radeon kernel
# drivers for the glamor/DRI3 render node, so on modern AMD (amdgpu) or
# NVIDIA (nvidia, KMS/GBM mode only - nvidia-drm.modeset=1, driver >=515)
# GPUs Xorg logs "unsupported render node" and X11 clients fall back to
# llvmpipe. No-op without /dev/dri mapped in (see init-video).
sed -i 's/"i915 radeon"/"i915 radeon amdgpu nvidia"/' /etc/X11/xrdp/xorg.conf
grep -q 'DRMAllowList" "i915 radeon amdgpu nvidia"' /etc/X11/xrdp/xorg.conf

# abc ships with shell /bin/false; xfce4-terminal execs it per window,
# so it needs a real shell or every terminal closes instantly.
echo "**** abc shell ****"
usermod -s /bin/bash abc
echo "abc ALL=(ALL) NOPASSWD:ALL" | tee -a /etc/sudoers
EOF

# s6-rc services, startwm.sh, xfconf defaults. --chmod=0755 covers the
# scripts that need +x; harmless no-op on the rest.
COPY --chmod=0755 rdp-root/ /

# See init-xrdp-user.sh for RDP_PASSWORD / no-op fallback behavior.
ENV RDP_USER=abc

EXPOSE 3389

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD ["bash", "-c", "echo > /dev/tcp/127.0.0.1/3389 || exit 1"]

LABEL org.opencontainers.image.authors="gnzsnz"
LABEL org.opencontainers.image.source=https://github.com/gnzsnz/rdesktop-xfce
LABEL org.opencontainers.image.url=https://github.com/gnzsnz/rdesktop-xfce/pkgs/container/rdesktop-xfce
LABEL org.opencontainers.image.description="Docker image with XFCE4 and xrdp"
LABEL org.opencontainers.image.licenses="Apache License Version 2.0"
