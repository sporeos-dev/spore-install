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
| `/Library/Application Support/spore-os/store` | Package store (node manifests, one sub-dir per node) |
| `/Library/Application Support/spore-os/nodes.registry.yaml` | Node registry (paths + checksums) |
| `/Library/Application Support/spore-os/spored.sock` | Unix domain socket (created at runtime by spored) |
| `/Library/Logs/spore-os` | Daemon and node log files |

---

## macOS Binaries (installed to store subdirectories, mode 755)

| Path | Purpose |
|------|---------|
| `/Library/Application Support/spore-os/spored` | `spored` daemon |
| `/Library/Application Support/spore-os/store/spore/spore` | Main CLI entry point |
| `/Library/Application Support/spore-os/store/spore-shell/spore-shell` | Shell node |
| `/Library/Application Support/spore-os/store/spore-witness/spore-witness` | Witness node |
| `/Library/Application Support/spore-os/store/spore-log/spore-log` | Log node |

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
| `/Applications/Spore Shell.app` | `/Library/Application Support/spore-os/store/spore-shell/spore-shell` via Terminal |
| `/Applications/Spore Witness.app` | `/Library/Application Support/spore-os/store/spore-witness/spore-witness` via Terminal |

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
| `/var/lib/spore-os/store` | Package store (node manifests, one sub-dir per node) |
| `/var/lib/spore-os/nodes.registry.yaml` | Node registry (paths + checksums) |
| `/var/lib/spore-os/spored.sock` | Unix domain socket (created at runtime by spored) |
| `/var/log/spore-os` | Daemon and node log files |

---

## Linux Binaries (installed to store subdirectories, mode 755)

| Path | Purpose |
|------|---------|
| `/var/lib/spore-os/spored` | `spored` daemon |
| `/var/lib/spore-os/store/spore/spore` | Main CLI entry point |
| `/var/lib/spore-os/store/spore-shell/spore-shell` | Shell node |
| `/var/lib/spore-os/store/spore-witness/spore-witness` | Witness node |
| `/var/lib/spore-os/store/spore-log/spore-log` | Log node |

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
| `/usr/share/applications/spore-shell.desktop` | `/var/lib/spore-os/store/spore-shell/spore-shell` in shell terminal |
| `/usr/share/applications/spore-witness.desktop` | `/var/lib/spore-os/store/spore-witness/spore-witness` in shell terminal |