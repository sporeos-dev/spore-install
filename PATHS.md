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

# Spore OS — Windows Installed Paths

This document is the source of truth for every path that `install.ps1` creates
or writes to. All other repos (`spored`, `spore-cli/*`) must use these exact
paths — no hardcoded alternatives.

---

## System identity

| What | Value |
|------|-------|
| Service account | `spore` (local user) |
| Service group | `Spore OS` (local group) |
| Windows service name | `spored` |

---

## Directories (created by installer, `spore` account has `FullControl`)

| Path | Purpose |
|------|---------|
| `%ProgramFiles%\spore-os` | Daemon binary root |
| `%ProgramFiles%\spore-os\bin` | CLI node binaries |
| `%ProgramData%\spore-os\data` | Persistent daemon data |
| `%ProgramData%\spore-os\hub` | Hub manifests |
| `%ProgramData%\spore-os\manifests` | Node manifests |
| `%ProgramData%\spore-os\run` | Runtime files (socket lives here) |
| `%ProgramData%\spore-os\logs` | Daemon and node log files |

---

## Binaries (installed to `%ProgramFiles%\spore-os\` and `\bin\`)

| Binary | Source |
|--------|---------|
| `%ProgramFiles%\spore-os\spored.exe` | `spored` daemon |
| `%ProgramFiles%\spore-os\bin\spore.exe` | Main CLI entry point |
| `%ProgramFiles%\spore-os\bin\spore-shell.exe` | Shell node |
| `%ProgramFiles%\spore-os\bin\spore-witness.exe` | Witness node |
| `%ProgramFiles%\spore-os\bin\spore-log.exe` | Log node |
| `%ProgramFiles%\spore-os\bin\spore-dialog.exe` | Dialog node |

Both `%ProgramFiles%\spore-os` and `%ProgramFiles%\spore-os\bin` are appended
to the **system** `PATH` by the installer.

`dist\` is split by architecture: `dist\amd64\` and `dist\arm64\`. The
installer detects the host architecture via `$env:PROCESSOR_ARCHITECTURE` and
copies the matching binaries.

---

## Windows service

| Item | Value |
|------|-------|
| Service name | `spored` |
| Registered by | `spored install` (self-registration) |
| Runs as | `.\spore` (local service account) |

---

## Start Menu shortcuts

| Path | Launches |
|------|----------|
| `%ProgramData%\Microsoft\Windows\Start Menu\Programs\Spore OS\Spore Shell.lnk` | `spore-shell.exe` |
| `%ProgramData%\Microsoft\Windows\Start Menu\Programs\Spore OS\Spore Witness.lnk` | `spore-witness.exe` |