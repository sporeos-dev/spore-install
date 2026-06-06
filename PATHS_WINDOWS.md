# Spore OS — Windows Installed Paths

This document is the source of truth for every path that `install.ps1` creates
or writes to. All other repos (`spored`, `spore-core-nodes/*`) must use these exact
paths — no hardcoded alternatives.

---

## Identity

| What | Value |
|------|-------|
| Process context | Current logged-in Windows user |
| Environment Override | `SPORE_DATA_DIR` set to `%LOCALAPPDATA%\spore-os` |

---

## Directories (created by installer under Local AppData user context)

| Path | Purpose |
|------|---------|
| `%LOCALAPPDATA%\spore-os` | Daemon binary root and persistent data |
| `%LOCALAPPDATA%\spore-os\bin` | CLI node binaries |
| `%LOCALAPPDATA%\spore-os\data` | Persistent daemon data |
| `%LOCALAPPDATA%\spore-os\hub` | Hub manifests |
| `%LOCALAPPDATA%\spore-os\manifests` | Node manifests |
| `%LOCALAPPDATA%\spore-os\run` | Runtime files (socket lives here) |
| `%LOCALAPPDATA%\spore-os\logs` | Daemon and node log files |

---

## Binaries (installed to `%LOCALAPPDATA%\spore-os\` and `\bin\`)

| Binary | Source |
|--------|---------|
| `%LOCALAPPDATA%\spore-os\spored.exe` | `spored` daemon |
| `%LOCALAPPDATA%\spore-os\bin\spore.exe` | Main CLI entry point |
| `%LOCALAPPDATA%\spore-os\bin\spore-shell.exe` | Shell node |
| `%LOCALAPPDATA%\spore-os\bin\spore-witness.exe` | Witness node |
| `%LOCALAPPDATA%\spore-os\bin\spore-log.exe` | Log node |
| `%LOCALAPPDATA%\spore-os\bin\spore-dialog.exe` | Dialog node |

Both `%LOCALAPPDATA%\spore-os` and `%LOCALAPPDATA%\spore-os\bin` are appended
to the **User** `PATH` by the installer.

`dist\` is split by architecture: `dist\amd64\` and `dist\arm64\`. The
installer detects the host architecture via `$env:PROCESSOR_ARCHITECTURE` and
copies the matching binaries.

---

## Background processes

| Item | Value |
|------|-------|
| Daemon name | `spored.exe` |
| Launched as | Standard hidden background process via installer |

---

## Start Menu shortcuts

| Path | Launches |
|------|----------|
| `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Spore OS\Spore Shell.lnk` | `spore-shell.exe` |
| `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Spore OS\Spore Witness.lnk` | `spore-witness.exe` |
