#!/usr/bin/env bash
# Copyright 2026 mharr
# SPDX-License-Identifier: Apache-2.0

# uninstall.sh — Spore OS macOS uninstaller
# Must be run with sudo.  Requires explicit confirmation before making any
# destructive changes.  All removal steps tolerate already-absent targets.

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
[[ "$EUID" -eq 0 ]] || die "uninstall.sh must be run with sudo.  Re-run: sudo $0"

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------
echo -e "${RED}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║          SPORE OS — UNINSTALL CONFIRMATION               ║"
echo "  ╠══════════════════════════════════════════════════════════╣"
echo "  ║  This will permanently remove:                           ║"
echo "  ║    • The spored daemon and all CLI node binaries         ║"
echo "  ║    • All Spore OS system directories and data            ║"
echo "  ║    • The _spore system user and group                    ║"
echo "  ║    • Spore Shell.app and Spore Witness.app               ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
read -r -p "  Type 'yes' to confirm: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || die "Aborted — you must type exactly: yes"

PLIST_PATH="/Library/LaunchDaemons/dev.sporeos.spored.plist"
SERVICE_LABEL="dev.sporeos.spored"
SYSTEM_USER="_spore"
SYSTEM_GROUP="_spore"
APP_SUPPORT="/Library/Application Support/spore-os"

NODES=(spore-shell spore-witness spore-log spore-dialog spore)

# ---------------------------------------------------------------------------
# 1. Stop the LaunchDaemon
# ---------------------------------------------------------------------------
step "Stopping LaunchDaemon (${SERVICE_LABEL})"

if launchctl print "system/${SERVICE_LABEL}" &>/dev/null; then
    launchctl bootout "system/${SERVICE_LABEL}" && success "Service ${SERVICE_LABEL} stopped"
else
    warn "Service ${SERVICE_LABEL} is not loaded — skipping"
fi

# ---------------------------------------------------------------------------
# 2. Remove the plist via spored uninstall
# ---------------------------------------------------------------------------
step "Removing LaunchDaemon plist"

if [[ -x /usr/local/bin/spored ]]; then
    if /usr/local/bin/spored uninstall 2>/dev/null; then
        success "spored uninstall completed"
    else
        warn "spored uninstall returned non-zero — attempting manual removal"
        rm -f "$PLIST_PATH" && success "Removed $PLIST_PATH" || true
    fi
else
    warn "/usr/local/bin/spored not found — removing plist directly"
    rm -f "$PLIST_PATH" && success "Removed $PLIST_PATH" || true
fi

# ---------------------------------------------------------------------------
# 3. Remove binaries from /usr/local/bin
# ---------------------------------------------------------------------------
step "Removing binaries from /usr/local/bin"

for bin in spored "${NODES[@]}"; do
    target="/usr/local/bin/${bin}"
    if [[ -f "$target" ]]; then
        rm -f "$target"
        success "Removed $target"
    else
        warn "$target not found — skipping"
    fi
done

# ---------------------------------------------------------------------------
# 4. Remove system directories
# ---------------------------------------------------------------------------
step "Removing system directories"

for path in \
    "$APP_SUPPORT" \
    "/Library/Logs/spore-os" \
    "/var/run/spore"
do
    if [[ -e "$path" ]]; then
        rm -rf "$path"
        success "Removed $path"
    else
        warn "$path not found — skipping"
    fi
done

# ---------------------------------------------------------------------------
# 5. Remove .app bundles
# ---------------------------------------------------------------------------
step "Removing application bundles"

for app in "Spore Shell.app" "Spore Witness.app"; do
    target="/Applications/${app}"
    if [[ -d "$target" ]]; then
        rm -rf "$target"
        success "Removed $target"
    else
        warn "$target not found — skipping"
    fi
done

# ---------------------------------------------------------------------------
# 6. Delete system user and group
# ---------------------------------------------------------------------------
step "Removing system user and group"

if dscl . -read "/Users/${SYSTEM_USER}" &>/dev/null; then
    dscl . -delete "/Users/${SYSTEM_USER}"
    success "User ${SYSTEM_USER} deleted"
else
    warn "User ${SYSTEM_USER} not found — skipping"
fi

if dscl . -read "/Groups/${SYSTEM_GROUP}" &>/dev/null; then
    dscl . -delete "/Groups/${SYSTEM_GROUP}"
    success "Group ${SYSTEM_GROUP} deleted"
else
    warn "Group ${SYSTEM_GROUP} not found — skipping"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo -e "\n${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  Spore OS has been successfully uninstalled.${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
