# Spore OS — unix-like Installed Paths (macOS & Linux)

This document is the source of truth for every path that `install.sh` creates
or writes to. All other repos (`spored`, `spore-core-nodes/*`) must use these exact
paths — no hardcoded alternatives.

---

## macOS System identity

| What | Value |
|------|-------|
| System user | `_spore` (UID 499) |
| System group | `_spore` (GID 499) |
| LaunchDaemon label | `dev.sporeos.spored` |

---

## macOS Directories (created by installer, owned by `_spore:_spore`)

| Path | Purpose |
|------|---------|
| `/Library/Application Support/spore-os/data` | Persistent daemon data |
| `/Library/Application Support/spore-os/hub` | Hub manifests |
| `/Library/Application Support/spore-os/manifests` | Node manifests |
| `/Library/Application Support/spore-os/run` | Runtime files (socket lives here) |
| `/Library/Logs/spore-os` | Daemon and node log files |
| `/var/run/spore` | Runtime directory (currently unused — see socket note below) |

---

## macOS Binaries (installed to `/usr/local/bin`, mode 755)

| Binary | Source |
|--------|--------|
| `/usr/local/bin/spored` | `spored` daemon |
| `/usr/local/bin/spore` | Main CLI entry point |
| `/usr/local/bin/spore-shell` | Shell node |
| `/usr/local/bin/spore-witness` | Witness node |
| `/usr/local/bin/spore-log` | Log node |

---

## macOS LaunchDaemon

| Path | Purpose |
|------|---------|
| `/Library/LaunchDaemons/dev.sporeos.spored.plist` | Registered by `spored install` |

Logs declared in the plist:
- stdout → `/Library/Logs/spore-os/dev.sporeos.spored.out.log`
- stderr → `/Library/Logs/spore-os/dev.sporeos.spored.err.log`

---

## macOS App bundles

| Path | Launches |
|------|---------|
| `/Applications/Spore Shell.app` | `/usr/local/bin/spore-shell` via Terminal |
| `/Applications/Spore Witness.app` | `/usr/local/bin/spore-witness` via Terminal |

---

# Spore OS — Linux Installed Paths

This document is the source of truth for every path that `install.sh` (Linux) creates
or writes to. All other repos (`spored`, `spore-core-nodes/*`) must use these exact
paths — no hardcoded alternatives.

---

## Linux System identity

| What | Value |
|------|-------|
| System user | `spore` (UID 499 if available, or dynamic) |
| System group | `spore` (GID 499 if available, or dynamic) |
| systemd service | `dev.sporeos.spored.service` |

---

## Linux Directories (created by installer, owned by `spore:spore`)

| Path | Purpose |
|------|---------|
| `/var/lib/spore-os/data` | Persistent daemon data |
| `/var/lib/spore-os/hub` | Hub manifests |
| `/var/lib/spore-os/manifests` | Node manifests |
| `/var/lib/spore-os/run` | Runtime files (socket lives here) |
| `/var/log/spore-os` | Daemon and node log files |
| `/run/spore` | Runtime directory (service-scoped transient directory) |

---

## Linux Binaries (installed to `/usr/local/bin`, mode 755)

| Binary | Source |
|--------|--------|
| `/usr/local/bin/spored` | `spored` daemon |
| `/usr/local/bin/spore` | Main CLI entry point |
| `/usr/local/bin/spore-shell` | Shell node |
| `/usr/local/bin/spore-witness` | Witness node |
| `/usr/local/bin/spore-log` | Log node |

---

## Linux systemd Service Unit

| Path | Purpose |
|------|---------|
| `/etc/systemd/system/dev.sporeos.spored.service` | systemd service description file |

Logs declared in the service file:
- stdout → `/var/log/spore-os/dev.sporeos.spored.out.log`
- stderr → `/var/log/spore-os/dev.sporeos.spored.err.log`

---

## Linux XDG Desktop Entries

| Path | Launches |
|------|---------|
| `/usr/share/applications/spore-shell.desktop` | `/usr/local/bin/spore-shell` in shell terminal |
| `/usr/share/applications/spore-witness.desktop` | `/usr/local/bin/spore-witness` in shell terminal |