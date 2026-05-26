# Spore OS — macOS Installed Paths

This document is the source of truth for every path that `install.sh` creates
or writes to. All other repos (`spored`, `spore-cli/*`) must use these exact
paths — no hardcoded alternatives.

---

## System identity

| What | Value |
|------|-------|
| System user | `_spore` (UID 499) |
| System group | `_spore` (GID 499) |
| LaunchDaemon label | `dev.sporeos.spored` |

---

## Directories (created by installer, owned by `_spore:_spore`)

| Path | Purpose |
|------|---------|
| `/Library/Application Support/spore-os/data` | Persistent daemon data |
| `/Library/Application Support/spore-os/hub` | Hub manifests |
| `/Library/Application Support/spore-os/manifests` | Node manifests |
| `/Library/Application Support/spore-os/run` | Runtime files (socket lives here) |
| `/Library/Logs/spore-os` | Daemon and node log files |
| `/var/run/spore` | Runtime directory (currently unused — see socket note below) |

---

## Binaries (installed to `/usr/local/bin`, mode 755)

| Binary | Source |
|--------|--------|
| `/usr/local/bin/spored` | `spored` daemon |
| `/usr/local/bin/spore` | Main CLI entry point |
| `/usr/local/bin/spore-shell` | Shell node |
| `/usr/local/bin/spore-witness` | Witness node |
| `/usr/local/bin/spore-log` | Log node |
| `/usr/local/bin/spore-dialog` | Dialog node |

---

## LaunchDaemon

| Path | Purpose |
|------|---------|
| `/Library/LaunchDaemons/dev.sporeos.spored.plist` | Registered by `spored install` |

Logs declared in the plist:
- stdout → `/Library/Logs/spore-os/dev.sporeos.spored.out.log`
- stderr → `/Library/Logs/spore-os/dev.sporeos.spored.err.log`

---

## App bundles

| Path | Launches |
|------|---------|
| `/Applications/Spore Shell.app` | `/usr/local/bin/spore-shell` via Terminal |
| `/Applications/Spore Witness.app` | `/usr/local/bin/spore-witness` via Terminal |

---

## Unix socket  ⚠️ MISMATCHED — needs alignment

This is the active bug. The two repos currently disagree:

| Repo | Socket path compiled in |
|------|------------------------|
| `spored` (daemon) | `/Library/Application Support/spore-os/run/spore.sock` |
| `spore-cli/spore` (CLI) | `/var/run/spore/spore.sock` |

**Pick one and update both repos to match.** The installer creates both parent
directories. Either path is valid; they just need to be the same.
