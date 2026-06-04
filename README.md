
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
| Linux | Planned |
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

## Install (Windows)

No packaged release yet. To install from a local build:

```powershell
cd windows
.\build.ps1        # builds dist\ with amd64 and arm64 binaries
```

Then, in an elevated (Administrator) PowerShell:

```powershell
.\dist\install.ps1
```

To uninstall:

```powershell
.\dist\uninstall.ps1
```

> [!NOTE]
> `build.ps1` requires the `DEV` environment variable to be set, pointing to
> the directory that contains the `spore-os` and `spore-cli` sibling repos.
> `install.ps1` and `uninstall.ps1` must be run in an **Administrator**
> PowerShell session.

---

## What gets installed

- `spored` — the hub daemon
  - macOS: runs as `_spore` via launchd
  - Windows: runs as the `spore` local service account via the Windows Service Manager
- `spore`, `spore-shell`, `spore-dialog`, `spore-log`, `spore-witness` — core nodes
- Platform-specific paths defined in [PATHS.md](PATHS.md)

---

## License

Apache-2.0 — see [LICENSE](LICENSE).
