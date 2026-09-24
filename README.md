# rdesktop-xfce

An RDP-reachable XFCE4 desktop on Ubuntu, built on
[`linuxserver/baseimage-ubuntu`](https://github.com/linuxserver/docker-baseimage-ubuntu)
(s6-overlay v3, no systemd).

This is a **spiritual continuation of the discontinued
[`linuxserver/rdesktop:ubuntu-xfce`](https://docs.linuxserver.io/deprecated_images/docker-rdesktop/)**
image, scoped down on purpose: XFCE4 only, no Openbox/app-container mode, no
other distros. LinuxServer stopped maintaining `rdesktop` with no direct
replacement (they now point RDP users at [Webtop](https://github.com/linuxserver/docker-webtop),
which is browser/Selkies-based, not RDP).

## Quick start

Preferred option is with [docker compose](./docker-compose.yml):

```bash
docker compose up -d
```

or with `docker run`:

```bash
docker run -d \
  --name=rdesktop-xfce \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Etc/UTC \
  -p 3389:3389 \
  -v ./config:/config \
  --shm-size=1gb \
  --restart unless-stopped \
  ghcr.io/gnzsnz/rdesktop-xfce:latest
```

Connect with any RDP client to port `3389`. Log in as `abc` (or your
`RDP_USER`). If you didn't set `RDP_PASSWORD`, check `docker logs
rdesktop-xfce` on first boot for the generated password (also saved at
`/config/.rdp_credentials`).

## Environment variables

| Variable | Default | Description |
| --- | --- | --- |
| `PUID` | `911` | UID the desktop session runs as. Match it to the owner of your `/config` bind mount. |
| `PGID` | `911` | GID counterpart to `PUID`. |
| `TZ` | `Etc/UTC` | Timezone, e.g. `Europe/London`. |
| `UMASK` | `022` | Default umask for files created in the session. |
| `RDP_USER` | `abc` | Login username. Only meaningful to change if you also rename/replace the baseimage's `abc` account yourself; left at `abc` in normal use. |
| `RDP_PASSWORD` | *(unset)* | RDP login password. If unset, a random 20-character password is generated once on first boot, printed to the container log, and persisted at `/config/.rdp_credentials` so it survives restarts. Set this explicitly for anything beyond throwaway/local use. |
| `FILE__RDP_PASSWORD` | *(unset)* | Docker/Swarm-secrets form of `RDP_PASSWORD` — point it at a file and its contents are read into `RDP_PASSWORD` at startup. Works for any `FILE__<VAR>` per the baseimage's standard convention. |
| `DOCKER_MODS` | *(unset)* | Apply a [LinuxServer mod](https://mods.linuxserver.io/) at startup, e.g. `linuxserver/mods:universal-package-install` + `INSTALL_PACKAGES=...` to add packages without a custom build. |

`PUID`/`PGID`/`TZ`/`UMASK`/`DOCKER_MODS`/`FILE__*` all come for free from
`linuxserver/baseimage-ubuntu` — nothing in this image overrides them.
`RDP_USER`/`RDP_PASSWORD` are specific to this image (see
`rdp-root/etc/s6-overlay/scripts/init-xrdp-user.sh`).

## Volumes

| Path | Purpose |
| --- | --- |
| `/config` | `abc`'s home directory. Also holds `/config/ssl/` (self-signed TLS cert/key, generated once) and `/config/.rdp_credentials` (auto-generated password, if any). Persist this. |
| `/custom-cont-init.d` | *(optional)* One-shot init scripts, run once at container start. Inherited from `linuxserver/baseimage-ubuntu` — see [Custom Scripts](https://docs.linuxserver.io/general/container-customization/#custom-scripts). |
| `/custom-services.d` | *(optional)* Long-running services, s6-supervised. Same LinuxServer convention as above. |

## Ports

| Port | Purpose |
| --- | --- |
| `3389/tcp` | RDP |

## Notes

- **`--security-opt seccomp=unconfined`** is recommended (as it was for the
  old image) — Firefox needs syscalls Docker's default seccomp profile blocks.
- **`--security-opt apparmor=unconfined`** is recommended — GNOME's
  image loader (`glycin-loaders`, pulled in transitively by XFCE/GVFS)
  decodes every icon in a `bwrap` sandbox. If `bwrap` can't run, glycin
  has no fallback, and XFCE treats some failed icon loads as fatal
  (`Gtk:ERROR:...assertion failed (error == NULL)`), aborting
  xfce4-session and killing the RDP session ("Window manager exited
  quickly" in `xrdp-sesman.log`). `bwrap` is blocked by:
  - Docker's default AppArmor profile, which denies the mounts it needs
    (`Failed to make / slave: Permission denied`) — lifted by
    `apparmor=unconfined`;
  - hosts with `kernel.apparmor_restrict_unprivileged_userns=1` (Ubuntu
    23.10+ default), which strip capabilities from the user namespace it
    creates (`setting up uid map: Permission denied`) — no container
    option lifts this.

  The image ships a `bwrap` shim in `/usr/local/bin` that uses the real
  `/usr/bin/bwrap` when it works and otherwise runs the loader
  unsandboxed (the same trust level as the in-process gdk-pixbuf loaders
  of Ubuntu 24.04 and earlier), so the desktop works either way;
  `apparmor=unconfined` just lets you keep the sandbox on hosts without
  the userns restriction.
- **`shm_size: 1gb`** — Firefox and other Chromium/Gecko-based apps can
  crash under Docker's default 64MB `/dev/shm`.
- Firefox from Mozilla's own APT repo
- Cert/key generated once per deployment, persisted at `/config/ssl/cert.pem`+`cert.key`.
- RDP password: random-generated on first boot if `RDP_PASSWORD` isn't
set, persisted to `/config/.rdp_credentials`, printed once to the
container log.

## Troubleshooting

### Firefox: youtube.com / music.youtube.com load blank (Docker Desktop macOS/Windows)

**Problem**: Docker Desktop's bind mount for `./config` doesn't support
the file locking Firefox's IndexedDB (SQLite) needs, so YouTube's
IndexedDB-heavy app fails to init and renders blank. Same risk on Windows
whenever `/config` is bound from the Windows side (Hyper-V backend, or a
WSL2 path under `/mnt/c/...`); a `./config` that lives natively inside
WSL2 isn't affected.

**Fix**: give Firefox's profile its own named volume instead of the bind
mount — uncomment `firefox-profile:/config/.config/mozilla/firefox` and
`./custom-cont-init.d:/custom-cont-init.d` in
[`docker-compose.yml`](./docker-compose.yml). The init script
(`custom-cont-init.d/10-chown-firefox-profile.sh`) fixes the fresh
volume's `root:root` ownership so Firefox can write to it.

## License

```text
Copyright 2026 gnzsnz

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
```
