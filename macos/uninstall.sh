#!/usr/bin/env bash
# Copyright 2026 Matt Harrison
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
echo "  ║    • The hyphae user agent (current user)               ║"
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

NODES=(spore-shell spore-witness spore-log spore)
HYPHAE_AGENT_LABEL="dev.sporeos.agent"

# ---------------------------------------------------------------------------
# Detect the real (non-root) user who invoked sudo
# ---------------------------------------------------------------------------
REAL_USER="${SUDO_USER:-}"
[[ -z "$REAL_USER" ]] && REAL_USER="$(logname 2>/dev/null || true)"
[[ "$REAL_USER" == "root" ]] && REAL_USER=""
if [[ -n "$REAL_USER" ]]; then
    REAL_UID="$(id -u "$REAL_USER")"
    REAL_HOME="$(dscl . -read "/Users/$REAL_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
fi

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

if [[ -x "${APP_SUPPORT}/spored" ]]; then
    if "${APP_SUPPORT}/spored" uninstall 2>/dev/null; then
        success "spored uninstall completed"
    else
        warn "spored uninstall returned non-zero — attempting manual removal"
        rm -f "$PLIST_PATH" && success "Removed $PLIST_PATH" || true
    fi
else
    warn "${APP_SUPPORT}/spored not found — removing plist directly"
    rm -f "$PLIST_PATH" && success "Removed $PLIST_PATH" || true
fi

# ---------------------------------------------------------------------------
# 2b. Stop and unregister hyphae user agent
# ---------------------------------------------------------------------------
step "Stopping hyphae user agent"

if [[ -n "$REAL_USER" ]]; then
    AGENT_PLIST="$REAL_HOME/Library/LaunchAgents/${HYPHAE_AGENT_LABEL}.plist"
    if launchctl print "gui/${REAL_UID}/${HYPHAE_AGENT_LABEL}" &>/dev/null; then
        launchctl bootout "gui/${REAL_UID}" "$AGENT_PLIST" \
            && success "Hyphae agent stopped for ${REAL_USER}"
    else
        warn "Hyphae agent not running for ${REAL_USER} — skipping bootout"
    fi
    if [[ -x "${APP_SUPPORT}/store/hyphae/hyphae" ]]; then
        sudo -H -u "$REAL_USER" "${APP_SUPPORT}/store/hyphae/hyphae" uninstall 2>/dev/null \
            && success "Hyphae LaunchAgent plist removed" \
            || warn "hyphae uninstall returned non-zero (plist may already be absent)"
    else
        rm -f "$AGENT_PLIST" && success "Removed $AGENT_PLIST" || true
    fi
else
    warn "Could not determine the invoking user — hyphae agent not auto-deregistered."
    warn "Run as the target user: hyphae uninstall"
fi

# ---------------------------------------------------------------------------
# 3. Remove symlinks
# ---------------------------------------------------------------------------
step "Removing symlinks"

if [[ -L /usr/local/bin/spore ]]; then
    rm -f /usr/local/bin/spore
    success "Removed /usr/local/bin/spore"
else
    warn "/usr/local/bin/spore not found — skipping"
fi

if [[ -L /usr/local/bin/hyphae ]]; then
    rm -f /usr/local/bin/hyphae
    success "Removed /usr/local/bin/hyphae"
else
    warn "/usr/local/bin/hyphae not found — skipping"
fi

# ---------------------------------------------------------------------------
# 4. Remove system directories
# ---------------------------------------------------------------------------
step "Removing system directories"

for path in \
    "$APP_SUPPORT" \
    "/Library/Logs/spore-os"
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
