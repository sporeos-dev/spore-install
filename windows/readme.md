# Install Spore OS (Windows)

Extract the release archive and open its `dist` folder in PowerShell:

```powershell
Expand-Archive .\spore-os-install-windows.zip -DestinationPath .
cd .\dist
```

If upgrading from the old user-level installation, first run the following
in that user's **non-elevated** PowerShell. It permanently removes the
legacy user directory and its data; back up anything you need first.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\remove-legacy-install.ps1
```

Open an **administrator** PowerShell, change to the extracted `dist` folder,
and install the machine components:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-machine.ps1
```

Then, in each signed-in user's **non-elevated** PowerShell in `dist`, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register-user.ps1
```

The machine installer starts SporeD as `LocalService`. User registration
starts Hyphae and sets it to run at sign-in, adds Start menu shortcuts and
the `spore` command to the user PATH, and enables PowerShell Tab hints.
Restart terminal sessions to load the PATH and hints.

## Uninstall

From each user's **non-elevated** PowerShell in `dist`, remove their
integrations:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\unregister-user.ps1
```

Then, from an **administrator** PowerShell in `dist`, remove the machine
service and binaries:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall-machine.ps1
```

Machine data in `%ProgramData%\spore-os\data` is preserved.
