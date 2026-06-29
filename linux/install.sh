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

SERVICE_LABEL="dev.sporeos.spored"
APP_SUPPORT="/var/lib/spore-os"

NODES=(spore-shell spore-witness spore-log spore)

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
    "${APP_SUPPORT}/store"
    "/var/log/spore-os"
)

for dir in "${DIRS[@]}"; do
    mkdir -p "$dir"
    chown "${SYSTEM_USER}:${SYSTEM_GROUP}" "$dir"
    chmod 755 "$dir"
    success "$dir"
done

# ---------------------------------------------------------------------------
# 3. Install binaries to store
# ---------------------------------------------------------------------------
step "Installing binaries to store (${ARCH_DIR})"

[[ -f "$DIST_DIR/$ARCH_DIR/spored" ]] || die "Binary not found: $DIST_DIR/$ARCH_DIR/spored. Did you build first?"

install -m 755 "$DIST_DIR/$ARCH_DIR/spored" "${APP_SUPPORT}/spored"
chown "${SYSTEM_USER}:${SYSTEM_GROUP}" "${APP_SUPPORT}/spored"
success "Installed spored → ${APP_SUPPORT}/spored"

for node in "${NODES[@]}"; do
    [[ -f "$DIST_DIR/$ARCH_DIR/bin/$node" ]] || die "Binary not found: $DIST_DIR/$ARCH_DIR/bin/$node."
    mkdir -p "${APP_SUPPORT}/store/${node}"
    chown "${SYSTEM_USER}:${SYSTEM_GROUP}" "${APP_SUPPORT}/store/${node}"
    chmod 755 "${APP_SUPPORT}/store/${node}"
    install -m 755 "$DIST_DIR/$ARCH_DIR/bin/$node" "${APP_SUPPORT}/store/${node}/${node}"
    chown "${SYSTEM_USER}:${SYSTEM_GROUP}" "${APP_SUPPORT}/store/${node}/${node}"
    success "Installed $node → store/${node}/${node}"
done

# ---------------------------------------------------------------------------
# 3b. Symlink spore CLI into /usr/local/bin
# ---------------------------------------------------------------------------
step "Symlinking spore CLI to /usr/local/bin"

ln -sf "${APP_SUPPORT}/store/spore/spore" /usr/local/bin/spore
success "Symlinked: /usr/local/bin/spore → store/spore/spore"
# ---------------------------------------------------------------------------
step "Installing hub manifest"

[[ -f "$DIST_DIR/spored.manifest.spore.yaml" ]] || die "Manifest not found: $DIST_DIR/spored.manifest.spore.yaml"

install -m 644 "$DIST_DIR/spored.manifest.spore.yaml" \
    "${APP_SUPPORT}/spored.manifest.spore.yaml"
chown "${SYSTEM_USER}:${SYSTEM_GROUP}" "${APP_SUPPORT}/spored.manifest.spore.yaml"
success "Hub manifest installed at ${APP_SUPPORT}/"

# ---------------------------------------------------------------------------
# 5. Register systemd service and start it
# ---------------------------------------------------------------------------
step "Registering systemd service (${SERVICE_LABEL})"

# Ensure log files exist with correct permissions before starting
touch /var/log/spore-os/${SERVICE_LABEL}.out.log /var/log/spore-os/${SERVICE_LABEL}.err.log
chown "${SYSTEM_USER}:${SYSTEM_GROUP}" /var/log/spore-os/${SERVICE_LABEL}.out.log /var/log/spore-os/${SERVICE_LABEL}.err.log
chmod 640 /var/log/spore-os/${SERVICE_LABEL}.out.log /var/log/spore-os/${SERVICE_LABEL}.err.log

cat <<EOF > /etc/systemd/system/${SERVICE_LABEL}.service
[Unit]
Description=Spore OS Daemon - spored
After=network.target

[Service]
Type=simple
User=${SYSTEM_USER}
Group=${SYSTEM_GROUP}
WorkingDirectory=${APP_SUPPORT}
ExecStart=${APP_SUPPORT}/spored
Restart=on-failure
StandardOutput=append:/var/log/spore-os/${SERVICE_LABEL}.out.log
StandardError=append:/var/log/spore-os/${SERVICE_LABEL}.err.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${SERVICE_LABEL}.service
systemctl restart ${SERVICE_LABEL}.service
success "systemd service ${SERVICE_LABEL}.service registered and started"

# ---------------------------------------------------------------------------
# 6. Install node manifests to store and write registry
# ---------------------------------------------------------------------------
step "Installing node manifests to store"

REGISTRY_FILE="${APP_SUPPORT}/nodes.registry.yaml"

shopt -s nullglob
manifests=("$DIST_DIR/nodes/"*.manifest.spore.yaml)
shopt -u nullglob

if [[ ${#manifests[@]} -eq 0 ]]; then
    warn "No node manifests found in ${DIST_DIR}/nodes/ — skipping registry write"
else
    # Write YAML registry header
    {
        printf '# Spore OS Node Registry — managed by installer/spored, do not edit manually\n'
        printf 'version: 1\n'
        printf 'nodes:\n'
    } > "$REGISTRY_FILE"

    for manifest in "${manifests[@]}"; do
        node_name="$(basename "$manifest" .manifest.spore.yaml)"
        node_store_dir="${APP_SUPPORT}/store/${node_name}"
        mkdir -p "$node_store_dir"
        chown "${SYSTEM_USER}:${SYSTEM_GROUP}" "$node_store_dir"
        chmod 755 "$node_store_dir"
        dest_manifest="${node_store_dir}/$(basename "$manifest")"
        cp "$manifest" "$dest_manifest"
        chown "${SYSTEM_USER}:${SYSTEM_GROUP}" "$dest_manifest"
        chmod 644 "$dest_manifest"
        success "Stored manifest: $dest_manifest"

        # Compute SHA-256 checksum
        hash="$(sha256sum "$dest_manifest" | awk '{print $1}')"

        # Append YAML entry
        {
            printf '  - name: %s\n' "$node_name"
            printf '    manifest: %s\n' "$dest_manifest"
            printf "    checksum: 'sha256:%s'\n" "$hash"
        } >> "$REGISTRY_FILE"
    done

    chown "${SYSTEM_USER}:${SYSTEM_GROUP}" "$REGISTRY_FILE"
    chmod 644 "$REGISTRY_FILE"
    success "Node registry written to $REGISTRY_FILE"
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

create_desktop_entry "Spore Shell"   "spore-shell.desktop"   "${APP_SUPPORT}/store/spore-shell/spore-shell"
create_desktop_entry "Spore Witness" "spore-witness.desktop" "${APP_SUPPORT}/store/spore-witness/spore-witness"

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
