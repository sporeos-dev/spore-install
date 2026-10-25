
<!-- PREAMBLE BEGIN -->
> For project overview, contributing guidelines, code of conduct, security policy,
> and licensing information, see the
> [sporeos-dev organization README](https://github.com/sporeos-dev/.github).

> [!WARNING]
> **Alpha Software: Use at Your Own Risk.**
> Spore OS is currently in an alpha state.
> It is under active development, breaking changes are expected frequently.
> Do not use in production environments.
<!-- PREAMBLE FIN -->

# spore-install

Build, packaging, and installation scripts for Spore OS.

This is the release repo — it produces the distributable artifacts as users install.

**Status:** Active development. No releases yet.

---

## Platforms

| Platform | Status |
| :--- | :--- |
| macOS (arm64 + amd64 universal) | In development |
| Linux | In development |
| Windows (amd64 + arm64) | In development |

---

## Install (macOS)

No packaged release yet. To install from a local build:

```sh
cd macos
make release       # builds dist/ with all binaries
sudo ./install.sh  # installs to system paths, creates _spore user, registers launchd service
```

To uninstall:

```sh
sudo macos/uninstall.sh
```

---

## Install (Linux)

No packaged release yet. To install from a local build:

```sh
# Setup/install dependencies (shellcheck optional for development)
make setup

# Build-linux stages both amd64 and arm64 binaries in dist/
make release-linux

# Install to system paths (detects host architecture automatically),
# creates spore system user, registers and starts spored systemd service
sudo dist/install.sh
```

To uninstall:

```sh
sudo dist/uninstall.sh
```

---

## Install (Windows)

No packaged release yet. To install from a local build:

```powershell
cd windows
.\build.ps1        # builds dist\ for the native architecture
```

If migrating from the earlier user-level layout, remove that user's legacy
state from a non-elevated PowerShell:

```powershell
.\dist\remove-legacy-install.ps1
```

Install machine-owned components from an elevated PowerShell:

```powershell
Start-Process powershell -Verb RunAs -ArgumentList '-ExecutionPolicy Bypass -File .\dist\install-machine.ps1'
```

Then register the current signed-in user from a non-elevated PowerShell:

```powershell
.\dist\register-user.ps1
```

To remove the current user's integrations:

```powershell
.\dist\unregister-user.ps1
```

To remove the machine service and binaries:

```powershell
Start-Process powershell -Verb RunAs -ArgumentList '-ExecutionPolicy Bypass -File .\dist\uninstall-machine.ps1'
```

For development, to unregister the current user, remove the existing machine
installation, rebuild, reinstall, and register that user again in one step,
run this from a non-elevated developer PowerShell:

```powershell
.\reinstall.ps1
```

> [!NOTE]
> `build.ps1` requires the `DEV` environment variable to be set, pointing to
> the directory that contains the `spore-os` and `spore-core-nodes` sibling repos.
> `install-machine.ps1` and `uninstall-machine.ps1` require elevation.
> `register-user.ps1`, `unregister-user.ps1`, and
> `remove-legacy-install.ps1` must run from the signed-in user's
> non-elevated session. The machine installer runs SporeD as the
> low-privilege `LocalService` account. User registration creates Hyphae's
> per-user scheduled task. Restart terminal sessions after registration to
> refresh `PATH` and load PowerShell Tab hints for commands beginning with
> `spore`. Standard `cmd.exe` remains PATH-only.

---

## What gets installed

- `spored` — the hub daemon
  - macOS: runs as `_spore` via launchd
  - Windows: runs as `LocalService` via the Service Control Manager
- `spore`, `spore-shell`, `spore-log`, `spore-witness` — core nodes
- `store` — store node
- Platform-specific paths defined in [PATHS_UNIX.md](PATHS_UNIX.md) and [PATHS_WINDOWS.md](PATHS_WINDOWS.md)

---

## License

Apache-2.0 — see [LICENSE](LICENSE).
