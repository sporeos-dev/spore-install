#!/usr/bin/env bash
# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# install.sh — Spore OS Linux installer
# Must be run from the dist/ directory (or alongside dist/ contents) with sudo.
# Supports Ubuntu, Debian, Fedora, and openSUSE. Safe to re-run as an upgrade.

set -euo pipefail

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

step()    { echo -e "\n${CYAN}${BOLD}▶ $*${NC}"; }
success() { echo -e "${GREEN}✓ $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠ $*${NC}"; }
die()     { echo -e "${RED}✗ $*${NC}" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Must be root
# ---------------------------------------------------------------------------
[[ "$EUID" -eq 0 ]] || die "install.sh must be run with sudo.  Re-run: sudo $0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)        ARCH_DIR="amd64" ;;
    aarch64|arm64) ARCH_DIR="arm64" ;;
    *)             die "Unsupported architecture: $ARCH" ;;
esac

# Locate correct DIST_DIR containing $ARCH_DIR/spored
if [[ -f "$SCRIPT_DIR/$ARCH_DIR/spored" ]]; then
    DIST_DIR="$SCRIPT_DIR"
elif [[ -f "$SCRIPT_DIR/../dist/$ARCH_DIR/spored" ]]; then
    DIST_DIR="$SCRIPT_DIR/../dist"
elif [[ -f "$SCRIPT_DIR/dist/$ARCH_DIR/spored" ]]; then
    DIST_DIR="$SCRIPT_DIR/dist"
else
    # Fallback to SCRIPT_DIR
    DIST_DIR="$SCRIPT_DIR"
fi

SYSTEM_USER="spore"
SYSTEM_GROUP="spore"
USER_ID=499
GROUP_ID=499

SERVICE_LABEL="spored"
APP_SUPPORT="/var/lib/spore-os"

NODES=(spore-shell spore-witness spore-log spore-dialog spore)

# ---------------------------------------------------------------------------
# 1. Create system group and user
# ---------------------------------------------------------------------------
step "Creating system user and group: ${SYSTEM_GROUP} / ${SYSTEM_USER}"

if ! getent group "$SYSTEM_GROUP" &>/dev/null; then
    # Try creating group with GID 499
    if groupadd -r -g "$GROUP_ID" "$SYSTEM_GROUP" &>/dev/null; then
        success "Group ${SYSTEM_GROUP} created (GID ${GROUP_ID})"
    else
        # Fallback to next available GID
        groupadd -r "$SYSTEM_GROUP"
        success "Group ${SYSTEM_GROUP} created"
    fi
else
    warn "Group ${SYSTEM_GROUP} already exists — skipping"
fi

if ! getent passwd "$SYSTEM_USER" &>/dev/null; then
    # Locate valid nologin shell
    NOLOGIN="/sbin/nologin"
    if [[ ! -x "$NOLOGIN" ]]; then NOLOGIN="/usr/sbin/nologin"; fi
    if [[ ! -x "$NOLOGIN" ]]; then NOLOGIN="/bin/false"; fi

    # Try creating user with UID 499
    if useradd -r -g "$SYSTEM_GROUP" -u "$USER_ID" -d "$APP_SUPPORT" -s "$NOLOGIN" -c "Spore OS system user" "$SYSTEM_USER" &>/dev/null; then
        success "User ${SYSTEM_USER} created (UID ${USER_ID})"
    else
        # Fallback to next available UID
        useradd -r -g "$SYSTEM_GROUP" -d "$APP_SUPPORT" -s "$NOLOGIN" -c "Spore OS system user" "$SYSTEM_USER"
        success "User ${SYSTEM_USER} created"
    fi
else
    warn "User ${SYSTEM_USER} already exists — skipping"
fi

# ---------------------------------------------------------------------------
# 2. Create required system directories
# ---------------------------------------------------------------------------
step "Creating system directories"

declare -a DIRS=(
    "${APP_SUPPORT}/data"
    "${APP_SUPPORT}/hub"
    "${APP_SUPPORT}/manifests"
    "${APP_SUPPORT}/run"
    "/var/log/spore-os"
)

for dir in "${DIRS[@]}"; do
    mkdir -p "$dir"
    chown "${SYSTEM_USER}:${SYSTEM_GROUP}" "$dir"
    chmod 755 "$dir"
    success "$dir"
done

# ---------------------------------------------------------------------------
# 3. Install binaries to /usr/local/bin
# ---------------------------------------------------------------------------
step "Installing binaries to /usr/local/bin (${ARCH_DIR})"

[[ -f "$DIST_DIR/$ARCH_DIR/spored" ]] || die "Binary not found: $DIST_DIR/$ARCH_DIR/spored. Did you build first?"

install -m 755 "$DIST_DIR/$ARCH_DIR/spored" /usr/local/bin/spored
success "Installed spored"

for node in "${NODES[@]}"; do
    [[ -f "$DIST_DIR/$ARCH_DIR/bin/$node" ]] || die "Binary not found: $DIST_DIR/$ARCH_DIR/bin/$node."
    install -m 755 "$DIST_DIR/$ARCH_DIR/bin/$node" "/usr/local/bin/$node"
    success "Installed $node"
done

# ---------------------------------------------------------------------------
# 4. Install hub manifest
# ---------------------------------------------------------------------------
step "Installing hub manifest"

[[ -f "$DIST_DIR/spored.manifest.spore.yaml" ]] || die "Manifest not found: $DIST_DIR/spored.manifest.spore.yaml"

install -m 644 "$DIST_DIR/spored.manifest.spore.yaml" \
    "${APP_SUPPORT}/hub/spored.manifest.spore.yaml"
chown "${SYSTEM_USER}:${SYSTEM_GROUP}" "${APP_SUPPORT}/hub/spored.manifest.spore.yaml"
success "Hub manifest installed at ${APP_SUPPORT}/hub/"

# ---------------------------------------------------------------------------
# 5. Register systemd service and start it
# ---------------------------------------------------------------------------
step "Registering systemd service (${SERVICE_LABEL})"

# Ensure log files exist with correct permissions before starting
touch /var/log/spore-os/spored.out.log /var/log/spore-os/spored.err.log
chown "${SYSTEM_USER}:${SYSTEM_GROUP}" /var/log/spore-os/spored.out.log /var/log/spore-os/spored.err.log
chmod 640 /var/log/spore-os/spored.out.log /var/log/spore-os/spored.err.log

cat <<EOF > /etc/systemd/system/spored.service
[Unit]
Description=Spore OS Daemon - spored
After=network.target

[Service]
Type=simple
User=${SYSTEM_USER}
Group=${SYSTEM_GROUP}
WorkingDirectory=${APP_SUPPORT}
ExecStart=/usr/local/bin/spored
Restart=on-failure
StandardOutput=append:/var/log/spore-os/spored.out.log
StandardError=append:/var/log/spore-os/spored.err.log

# Ensure daemon runtime directory /run/spore
RuntimeDirectory=spore
RuntimeDirectoryMode=0755

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable spored.service
systemctl restart spored.service
success "systemd service spored.service registered and started"

# ---------------------------------------------------------------------------
# 6. Install node manifests, then restart daemon
# ---------------------------------------------------------------------------
step "Installing node manifests"

shopt -s nullglob
manifests=("$DIST_DIR/nodes/"*.manifest.spore.yaml)
shopt -u nullglob

if [[ ${#manifests[@]} -eq 0 ]]; then
    warn "No node manifests found in ${DIST_DIR}/nodes/ — skipping"
else
    # Allow the daemon a brief moment to open its socket/initialize
    sleep 0.5
    for manifest in "${manifests[@]}"; do
        if /usr/local/bin/spored install "$manifest" 2>/dev/null; then
            success "Installed manifest: $(basename "$manifest")"
        else
            warn "Could not register $(basename "$manifest") via spored — staging manifest file instead"
            cp "$manifest" "${APP_SUPPORT}/manifests/$(basename "$manifest")"
            chown "${SYSTEM_USER}:${SYSTEM_GROUP}" "${APP_SUPPORT}/manifests/$(basename "$manifest")"
        fi
    done

    step "Restarting daemon to load manifests"
    systemctl restart spored.service
    success "Daemon restarted"
fi

# ---------------------------------------------------------------------------
# 7. Create .desktop launcher entries for XDG-compliant desktop environments
# ---------------------------------------------------------------------------
step "Creating desktop launcher shortcuts"

create_desktop_entry() {
    local name="$1"
    local filename="$2"
    local bin_path="$3"

    cat <<EOF > "/usr/share/applications/${filename}"
[Desktop Entry]
Type=Application
Name=${name}
Comment=Launch ${name} in Terminal
Exec=${bin_path}
Terminal=true
Icon=utilities-terminal
Categories=System;Utility;TerminalEmulator;
EOF

    chmod 644 "/usr/share/applications/${filename}"
    success "Created: /usr/share/applications/${filename}"
}

create_desktop_entry "Spore Shell" "spore-shell.desktop" "/usr/local/bin/spore-shell"
create_desktop_entry "Spore Witness" "spore-witness.desktop" "/usr/local/bin/spore-witness"

if command -v update-desktop-database &>/dev/null; then
    update-desktop-database /usr/share/applications/ || true
    success "Desktop database updated"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo -e "\n${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  Spore OS installation complete!${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
