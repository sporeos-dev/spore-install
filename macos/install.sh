#!/usr/bin/env bash
# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# install.sh — Spore OS macOS installer
# Must be run from the dist/ directory (or alongside dist/ contents) with sudo.
# Safe to re-run as an upgrade — all steps are idempotent.

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
DIST_DIR="$SCRIPT_DIR"   # install.sh lives inside dist/ after build

SYSTEM_USER="_spore"
SYSTEM_GROUP="_spore"
USER_ID=499
GROUP_ID=499

PLIST_PATH="/Library/LaunchDaemons/dev.sporeos.spored.plist"
SERVICE_LABEL="dev.sporeos.spored"
APP_SUPPORT="/Library/Application Support/spore-os"

NODES=(spore-shell spore-witness spore-log spore)

# ---------------------------------------------------------------------------
# 1. Create system group and user
# ---------------------------------------------------------------------------
step "Creating system user and group: ${SYSTEM_GROUP} / ${SYSTEM_USER}"

if ! dscl . -read "/Groups/${SYSTEM_GROUP}" &>/dev/null; then
    dscl . -create "/Groups/${SYSTEM_GROUP}"
    dscl . -create "/Groups/${SYSTEM_GROUP}" PrimaryGroupID "$GROUP_ID"
    dscl . -create "/Groups/${SYSTEM_GROUP}" GroupMembership "$SYSTEM_USER"
    success "Group ${SYSTEM_GROUP} created (GID ${GROUP_ID})"
else
    warn "Group ${SYSTEM_GROUP} already exists — skipping"
fi

if ! dscl . -read "/Users/${SYSTEM_USER}" &>/dev/null; then
    dscl . -create "/Users/${SYSTEM_USER}"
    dscl . -create "/Users/${SYSTEM_USER}" UserShell          /usr/bin/false
    dscl . -create "/Users/${SYSTEM_USER}" NFSHomeDirectory   /var/empty
    dscl . -create "/Users/${SYSTEM_USER}" UniqueID           "$USER_ID"
    dscl . -create "/Users/${SYSTEM_USER}" PrimaryGroupID     "$GROUP_ID"
    success "User ${SYSTEM_USER} created (UID ${USER_ID})"
else
    warn "User ${SYSTEM_USER} already exists — skipping"
fi

# ---------------------------------------------------------------------------
# 2. Create required system directories
# ---------------------------------------------------------------------------
step "Creating system directories"

mkdir -p "${APP_SUPPORT}"
chown "${SYSTEM_USER}:${SYSTEM_GROUP}" "${APP_SUPPORT}"
success "${APP_SUPPORT}"

declare -a DIRS=(
    "${APP_SUPPORT}/data"
    "${APP_SUPPORT}/store"
    "/Library/Logs/spore-os"
)

for dir in "${DIRS[@]}"; do
    mkdir -p "$dir"
    chown "${SYSTEM_USER}:${SYSTEM_GROUP}" "$dir"
    success "$dir"
done

# ---------------------------------------------------------------------------
# 3. Install binaries to store
# ---------------------------------------------------------------------------
step "Installing binaries to store"

install -m 755 "$DIST_DIR/spored" "${APP_SUPPORT}/spored"
chown "${SYSTEM_USER}:${SYSTEM_GROUP}" "${APP_SUPPORT}/spored"
success "Installed spored → ${APP_SUPPORT}/spored"

for node in "${NODES[@]}"; do
    mkdir -p "${APP_SUPPORT}/store/${node}"
    install -m 755 "$DIST_DIR/bin/$node" "${APP_SUPPORT}/store/${node}/${node}"
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

install -m 644 "$DIST_DIR/spored.manifest.spore.yaml" \
    "${APP_SUPPORT}/spored.manifest.spore.yaml"
chown "${SYSTEM_USER}:${SYSTEM_GROUP}" "${APP_SUPPORT}/spored.manifest.spore.yaml"
success "Hub manifest installed at ${APP_SUPPORT}/"

# ---------------------------------------------------------------------------
# 5. Register LaunchDaemon and start it
# ---------------------------------------------------------------------------
step "Registering LaunchDaemon (${SERVICE_LABEL})"

"${APP_SUPPORT}/spored" install
success "LaunchDaemon plist registered at ${PLIST_PATH}"

if launchctl print "system/${SERVICE_LABEL}" &>/dev/null; then
    warn "Service ${SERVICE_LABEL} already loaded — skipping bootstrap"
else
    launchctl bootstrap system "${PLIST_PATH}"
    success "Service ${SERVICE_LABEL} started"
fi

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
        dest_manifest="${node_store_dir}/$(basename "$manifest")"
        cp "$manifest" "$dest_manifest"
        chown "${SYSTEM_USER}:${SYSTEM_GROUP}" "$dest_manifest"
        success "Stored manifest: $dest_manifest"

        # Compute SHA-256 checksum (macOS)
        hash="$(shasum -a 256 "$dest_manifest" | awk '{print $1}')"

        # Append YAML entry
        {
            printf '  - name: %s\n' "$node_name"
            printf '    manifest: %s\n' "$dest_manifest"
            printf "    checksum: 'sha256:%s'\n" "$hash"
        } >> "$REGISTRY_FILE"
    done

    chown "${SYSTEM_USER}:${SYSTEM_GROUP}" "$REGISTRY_FILE"
    success "Node registry written to $REGISTRY_FILE"
fi

# ---------------------------------------------------------------------------
# 7. Create .app launcher bundles in /Applications
# ---------------------------------------------------------------------------
step "Creating .app launcher bundles"

# create_app_bundle <app_path> <bundle_name> <bundle_id> <bin_path>
create_app_bundle() {
    local app_path="$1"
    local bundle_name="$2"
    local bundle_id="$3"
    local bin_path="$4"

    mkdir -p "${app_path}/Contents/MacOS"

    cat > "${app_path}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>         <string>${bundle_name}</string>
    <key>CFBundleExecutable</key>   <string>launcher</string>
    <key>CFBundleIdentifier</key>   <string>${bundle_id}</string>
    <key>CFBundleVersion</key>      <string>1.0</string>
    <key>CFBundlePackageType</key>  <string>APPL</string>
</dict>
</plist>
PLIST

    # Write the launcher script.  The outer heredoc marker is unquoted so that
    # ${bin_path} is expanded now; the inner <<'EOF_AS' is written literally so
    # it prevents expansion when the launcher actually runs.
    cat > "${app_path}/Contents/MacOS/launcher" <<EOF_LAUNCHER
#!/usr/bin/env bash
osascript <<'EOF_AS'
tell application "Terminal"
    activate
    do script "'${bin_path}'"
end tell
EOF_AS
EOF_LAUNCHER

    chmod +x "${app_path}/Contents/MacOS/launcher"
    success "Created: ${app_path}"
}

create_app_bundle \
    "/Applications/Spore Shell.app" \
    "Spore Shell" \
    "dev.sporeos.shell" \
    "${APP_SUPPORT}/store/spore-shell/spore-shell"

create_app_bundle \
    "/Applications/Spore Witness.app" \
    "Spore Witness" \
    "dev.sporeos.witness" \
    "${APP_SUPPORT}/store/spore-witness/spore-witness"

step "Triggering Spotlight indexing"
mdimport "/Applications/Spore Shell.app"
mdimport "/Applications/Spore Witness.app"
success "Spotlight indexing triggered"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo -e "\n${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  Spore OS installation complete!${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
