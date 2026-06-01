
<!-- PREAMBLE BEGIN -->
> For project overview, contributing guidelines, code of conduct, security policy,
> and licensing information, see the
> [sporeos-dev organization README](https://github.com/sporeos-dev/.github).

> [!WARNING]
> **Alpha Software: Use at Your Own Risk**
> Spore OS is currently in an alpha state.
> It is under active development, breaking changes are expected frequently.
> Do not use in production environments.
<!-- PREAMBLE FIN -->

# spore-install

Build, packaging, and installation scripts for Spore OS.

This is the release repo — it produces the distributable artifacts that end users install.

**Status:** Active development. No releases yet.

---

## Platforms

| Platform | Status |
| :--- | :--- |
| macOS (arm64 + amd64 universal) | In development |
| Linux | Planned |
| Windows | Planned |

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

## What gets installed

- `spored` — the hub daemon, runs as system user `_spore` via launchd
- `spore`, `spore-shell`, `spore-dialog`, `spore-log`, `spore-witness` — core nodes
- System paths defined in [PATHS.md](PATHS.md)

---

## License

Apache-2.0 — see [LICENSE](LICENSE).
