# Install Spore OS (macOS)

v0.2 binaries aren't Apple-notarized yet, so run the installer **from Terminal**:

```sh
tar -xzf spore-os-install-macos-universal.tar.gz
cd dist
sudo ./install.sh
```

The installer clears macOS's download quarantine flag. If macOS still blocks a binary:

```sh
sudo xattr -dr com.apple.quarantine .
```

Uninstall: `sudo ./uninstall.sh`
