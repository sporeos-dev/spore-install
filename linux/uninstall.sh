#!/usr/bin/env bash
# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# uninstall.sh — Spore OS Linux uninstaller
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
echo "  ║          SPORE OS — LINUX UNINSTALL CONFIRMATION         ║"
echo "  ╠══════════════════════════════════════════════════════════╣"
echo "  ║  This will permanently remove:                           ║"
echo "  ║    • The spored daemon and all CLI node binaries         ║"
echo "  ║    • All Spore OS system directories and data            ║"
echo "  ║    • The spore system user and group                     ║"
echo "  ║    • Spore Shell and Spore Witness desktop entries       ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
read -r -p "  Type 'yes' to confirm: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || die "Aborted — you must type exactly: yes"

SERVICE_LABEL="dev.sporeos.spored"
SYSTEM_USER="spore"
SYSTEM_GROUP="spore"
APP_SUPPORT="/var/lib/spore-os"

NODES=(spore-shell spore-witness spore-log spore-dialog spore)

# ---------------------------------------------------------------------------
# 1. Stop and disable the systemd service
# ---------------------------------------------------------------------------
step "Stopping and disabling ${SERVICE_LABEL} service"

if systemctl is-active "${SERVICE_LABEL}.service" &>/dev/null; then
    systemctl stop "${SERVICE_LABEL}.service" && success "Service ${SERVICE_LABEL}.service stopped"
else
    warn "Service ${SERVICE_LABEL}.service is not active — skipping"
fi

if systemctl is-enabled "${SERVICE_LABEL}.service" &>/dev/null; then
    systemctl disable "${SERVICE_LABEL}.service" && success "Service ${SERVICE_LABEL}.service disabled"
else
    warn "Service ${SERVICE_LABEL}.service is not enabled — skipping"
fi

# ---------------------------------------------------------------------------
# 2. Run spored uninstall if binary exists
# ---------------------------------------------------------------------------
step "Attempting spored self-uninstall"

if [[ -x /usr/local/bin/spored ]]; then
    if /usr/local/bin/spored uninstall 2>/dev/null; then
        success "spored uninstall completed"
    else
        warn "spored uninstall returned non-zero — attempting manual removal"
        rm -f "/etc/systemd/system/${SERVICE_LABEL}.service" && success "Removed service file" || true
    fi
else
    warn "/usr/local/bin/spored not found — removing service file directly"
    rm -f "/etc/systemd/system/${SERVICE_LABEL}.service" && success "Removed service file" || true
fi

# Reload systemd configuration
systemctl daemon-reload

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
    "/var/log/spore-os" \
    "/run/spore" \
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
# 5. Remove desktop launcher entries
# ---------------------------------------------------------------------------
step "Removing desktop entries"

for entry in "spore-shell.desktop" "spore-witness.desktop"; do
    target="/usr/share/applications/${entry}"
    if [[ -f "$target" ]]; then
        rm -f "$target"
        success "Removed $target"
    else
        warn "$target not found — skipping"
    fi
done

if command -v update-desktop-database &>/dev/null; then
    update-desktop-database /usr/share/applications/ || true
fi

# ---------------------------------------------------------------------------
# 6. Delete system user and group
# ---------------------------------------------------------------------------
step "Removing system user and group"

if getent passwd "$SYSTEM_USER" &>/dev/null; then
    userdel "$SYSTEM_USER"
    success "User ${SYSTEM_USER} deleted"
else
    warn "User ${SYSTEM_USER} not found — skipping"
fi

if getent group "$SYSTEM_GROUP" &>/dev/null; then
    if groupdel "$SYSTEM_GROUP" &>/dev/null; then
        success "Group ${SYSTEM_GROUP} deleted"
    else
        # Often userdel will delete the primary private group automatically on modern systems
        warn "Could not delete group ${SYSTEM_GROUP} (may have been auto-deleted with user) — skipping"
    fi
else
    warn "Group ${SYSTEM_GROUP} not found — skipping"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo -e "\n${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  Spore OS has been successfully uninstalled.${NC}"
echo -e "\t- Log configurations and user configuration removed."
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
