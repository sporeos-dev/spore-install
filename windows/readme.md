# Install Spore OS (Windows)

Extract the archive and open `dist` in PowerShell:

```powershell
Expand-Archive .\spore-os-install-windows.zip -DestinationPath .
cd .\dist
```

The installer clears Windows download blocks. If Windows blocks the installer
itself, unblock the files first, **only for a release you trust**. Run this
only in `dist`: it unblocks every file there.

```powershell
Get-ChildItem -LiteralPath . -Recurse -File -Force | Unblock-File
```

Security software or organizational policies may still block files; check the
warning or contact your administrator. The commands below bypass the execution
policy only for the individual PowerShell process.

If upgrading from the old user-level installation, first run this in the
user's **non-elevated** PowerShell. It permanently deletes legacy data;
back it up first.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\remove-legacy-install.ps1
```

In an **administrator** PowerShell in `dist`, install the machine components:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-machine.ps1
```

In each user's **non-elevated** PowerShell in `dist`, register the user:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register-user.ps1
```

Restart terminals to load PATH and PowerShell Tab hints.

## Uninstall

In each user's **non-elevated** PowerShell in `dist`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\unregister-user.ps1
```

Then, in an **administrator** PowerShell in `dist`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall-machine.ps1
```

Machine data in `%ProgramData%\spore-os\data` is preserved.
