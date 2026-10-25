# Spore OS — Windows Installed Paths

This document is the target layout for the Windows machine-service
installation. It is the source of truth for future Windows installer, service,
and PAL changes.

The current user-level installer is a legacy alpha layout. It installs the
daemon under `%LOCALAPPDATA%\spore-os`; it does not provide the protected
SporeD service boundary described here.

---

## Identity and trust boundary

| Component | Identity | Role |
|---|---|---|
| SporeD | `NT AUTHORITY\LocalService` | Non-interactive hub service; owns authoritative Spore state |
| Machine installer | Elevated administrator process | Creates machine-owned files, ACLs, and service registration only |
| User registration | Signed-in Windows user | Registers that user's agent and terminal integrations |
| Hyphae | Signed-in Windows user | Per-user agent that reaches user space and performs OS-authenticated confirmation |
| Nodes, shell, and GUI | Signed-in Windows user | Normal user-space participants; never write authoritative hub state |

The SporeD service must not run as an administrator or as the installing user.
Machine installation uses administrator rights only to establish the service
and its access controls. Per-user registration must run outside the elevated
process, even when the same account completes User Account Control.

## Contract rules

The following rules apply to every Windows consumer, including SporeD,
client libraries, installers, and test fixtures:

- The production endpoint is `%ProgramData%\spore-os\spore.sock`.
  `LOCALAPPDATA` is never the default endpoint root for the machine-service
  layout.
- Registry `manifest` and `binary` values are serialized with forward slashes.
  This is a storage representation, not a Windows path comparison rule.
- Only the SporeD PAL may canonicalize an operating-system-reported executable
  path before comparing it with a registry path. On Windows that comparison
  must normalize separators and case. Nodes and client libraries must not
  implement Windows path normalization themselves.
- SporeD, client libraries, and installer scripts must use absolute contract
  paths; no component may depend on a process working directory.

---

## Machine-owned directories

The elevated installer creates these directories under `%ProgramData%\spore-os`.

| Path | Purpose | Required access |
|---|---|---|
| `%ProgramData%\spore-os` | SporeD binary root and local IPC endpoint parent directory | `LocalService`, `SYSTEM`, and Administrators: full control; Users: traverse/read/execute only |
| `%ProgramData%\spore-os\data` | Persistent hub state | `LocalService`, `SYSTEM`, and Administrators only |
| `%ProgramData%\spore-os\data\permissions.yaml` | Persisted capability allowances | `LocalService`, `SYSTEM`, and Administrators only |
| `%ProgramData%\spore-os\nodes.registry.yaml` | Installed-node registry, paths, and checksums | `LocalService`, `SYSTEM`, and Administrators only |
| `%ProgramData%\spore-os\store` | Installed hub-managed node binaries and manifests | `LocalService`, `SYSTEM`, and Administrators: modify; Users: read/execute only |
| `%ProgramData%\spore-os\logs` | SporeD logs | `LocalService`, `SYSTEM`, and Administrators only |
| `%ProgramData%\spore-os\spored.manifest.spore.yaml` | Hub manifest | `LocalService`, `SYSTEM`, and Administrators: modify; Users: read only |
| `%ProgramData%\spore-os\spore.sock` | Temporary AF_UNIX local endpoint | Created at runtime by SporeD; `LocalService`, `SYSTEM`, and Administrators: full control; Authenticated Users: read/write |

The installer must set explicit ACLs. It must not grant Users modify, create,
delete, or ACL-change access anywhere inside authoritative hub state.

Users require read/execute access to the machine node store because Hyphae and
ordinary nodes run in user space. That access does not permit them to replace
an installed binary, alter a manifest, or modify the registry.

---

## Machine-installed binaries

| Path | Purpose |
|---|---|
| `%ProgramData%\spore-os\spored.exe` | SporeD Windows service executable |
| `%ProgramData%\spore-os\store\spore\spore.exe` | Main CLI entry point |
| `%ProgramData%\spore-os\store\spore-shell\spore-shell.exe` | Shell node |
| `%ProgramData%\spore-os\store\spore-witness\spore-witness.exe` | Witness node |
| `%ProgramData%\spore-os\store\spore-log\spore-log.exe` | Log node |
| `%ProgramData%\spore-os\store\store\store.exe` | Store node |
| `%ProgramData%\spore-os\store\hyphae\hyphae.exe` | Per-user Hyphae agent executable |
| `%ProgramData%\spore-os\integrations\powershell.ps1` | PowerShell Tab hint integration |

The installer adds `%ProgramData%\spore-os\store\spore` to the invoking user's
`PATH` for the `spore` CLI. It must not expose a user-writable installation
location.

---

## SporeD service

| Setting | Value |
|---|---|
| Service name | `dev.sporeos.spored` |
| Display name | `Spore OS Daemon` |
| Account | `NT AUTHORITY\LocalService` |
| Executable | `%ProgramData%\spore-os\spored.exe` |
| Working directory | Not a service contract; SporeD uses absolute PAL paths |
| Startup | Automatic |

The service starts independently of any interactive user. It fails closed for
actions requiring user-space work or OS-authenticated confirmation when no
appropriate Hyphae agent is available.

---

## Per-user files and integrations

| Path or registration | Purpose |
|---|---|
| User Task Scheduler task `\dev.sporeos.HYPHAE.<SID>` | Starts the background Hyphae agent at user logon in that user's session |
| `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Spore OS` | Shell and Witness shortcuts for the user |
| `%USERPROFILE%\Documents\WindowsPowerShell\Profile.ps1` | Sources PowerShell Tab hint integration |
| `%USERPROFILE%\Documents\PowerShell\Profile.ps1` | Sources PowerShell 7 Tab hint integration |
| `%LOCALAPPDATA%\spore-os` | Reserved for non-authoritative per-user state only; never holds SporeD registry, permissions, socket, or service binaries |

User registration creates and starts Hyphae for the signed-in user running the
registration command. Other users register their own Hyphae agent after
sign-in. Machine installation must not create, update, or remove per-user
files, tasks, shortcuts, or profile entries.

Hyphae runs as a background process in the signed-in user's session. It has no
visible console window, so closing an unrelated terminal cannot stop it. It is
responsible for user-space operations
and for `HYPHAE.confirm`, which requires Windows Hello/PIN verification for
the current user. If Windows Hello/PIN is unavailable or unconfigured, the
confirmation fails closed. Hyphae never receives write access to SporeD's
authoritative directories.

The on-demand Dialog node is also a Windows GUI-subsystem executable. It
displays its requested native dialog without creating a console window; closing
an unrelated terminal must not cancel an active picker.

PowerShell Tab invokes Spore hints only when the current line begins with
`spore`; all other input keeps standard PowerShell completion. Standard
`cmd.exe` has no programmable Tab handler, so it remains PATH-only.

---

## Local IPC and peer identity

SporeD and nodes retain the existing local wire grammar. The PAL owns the
endpoint implementation.

Windows currently uses an AF_UNIX endpoint at
`%ProgramData%\spore-os\spore.sock`. Before the machine-service installer
uses this layout, PAL must enforce an endpoint-access policy appropriate for
the service-owned parent directory and retain the peer-identity contract:

- derive the peer PID from the operating system;
- resolve the peer executable path from that PID;
- verify the process against the installed node registry.

The socket path is an endpoint name, not authoritative state. It must be
removed when the service stops and recreated by SporeD at startup.

---

## Installation lifecycle

The target installer exposes four explicit operations. This mirrors Windows'
machine and per-user ownership boundaries rather than trying to cross identity
contexts inside one elevated script.

| Operation | Intended script | Runs as | Responsibilities |
|---|---|---|---|
| Machine install | `install-machine.ps1` | Administrator | Installs `%ProgramData%\spore-os`, applies machine ACLs, registers and starts SporeD, and removes the known old root Hyphae task when it targets the installed executable |
| User registration | `register-user.ps1` | Signed-in user | Registers Hyphae, adds the CLI to that user's `PATH`, and creates that user's terminal integrations and shortcuts |
| User unregistration | `unregister-user.ps1` | Signed-in user | Removes that user's Hyphae task, `PATH` entry, terminal integrations, and shortcuts |
| Machine uninstall | `uninstall-machine.ps1` | Administrator | Stops and removes SporeD and machine binaries; authoritative data is preserved unless a separate explicit data-removal operation is selected |
| Legacy cleanup | `remove-legacy-install.ps1` | Signed-in user | Removes only known legacy LocalAppData state and its `SPORE_DATA_DIR` value |

These names describe the target interface. Existing alpha scripts may be
reorganized to reach this contract, but must not combine machine and per-user
ownership in their final form.

---

## Legacy user-level layout

The old `%LOCALAPPDATA%\spore-os` installation is unsupported by the
machine-service model. The first machine-service installer requires a clean
uninstall/reinstall rather than automatic migration of its registry,
permissions, or node data.
