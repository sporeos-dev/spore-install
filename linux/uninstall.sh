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
echo "  ║    • The hyphae user agent (current user)               ║"
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
    REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
fi

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

if [[ -x "${APP_SUPPORT}/spored" ]]; then
    if "${APP_SUPPORT}/spored" uninstall 2>/dev/null; then
        success "spored uninstall completed"
    else
        warn "spored uninstall returned non-zero — attempting manual removal"
        rm -f "/etc/systemd/system/${SERVICE_LABEL}.service" && success "Removed service file" || true
    fi
else
    warn "${APP_SUPPORT}/spored not found — removing service file directly"
    rm -f "/etc/systemd/system/${SERVICE_LABEL}.service" && success "Removed service file" || true
fi

# Reload systemd configuration
systemctl daemon-reload

# ---------------------------------------------------------------------------
# 2b. Stop and unregister hyphae user agent
# ---------------------------------------------------------------------------
step "Stopping hyphae user agent"

if [[ -n "$REAL_USER" ]]; then
    AGENT_SERVICE="${HYPHAE_AGENT_LABEL}.service"
    XDG_RT="/run/user/${REAL_UID}"
    if [[ -d "$XDG_RT" ]]; then
        if sudo -u "$REAL_USER" XDG_RUNTIME_DIR="$XDG_RT" \
                systemctl --user is-active "$AGENT_SERVICE" &>/dev/null; then
            sudo -u "$REAL_USER" XDG_RUNTIME_DIR="$XDG_RT" \
                systemctl --user stop "$AGENT_SERVICE" \
                && success "Hyphae agent stopped for ${REAL_USER}"
        else
            warn "Hyphae agent not active for ${REAL_USER} — skipping stop"
        fi
        sudo -u "$REAL_USER" XDG_RUNTIME_DIR="$XDG_RT" \
            systemctl --user disable "$AGENT_SERVICE" 2>/dev/null || true
    else
        warn "${XDG_RT} not found — cannot stop hyphae agent via systemctl (not running?)"
    fi
    if [[ -x "${APP_SUPPORT}/store/hyphae/hyphae" ]]; then
        sudo -H -u "$REAL_USER" "${APP_SUPPORT}/store/hyphae/hyphae" uninstall 2>/dev/null \
            && success "Hyphae systemd user unit removed" \
            || warn "hyphae uninstall returned non-zero (unit may already be absent)"
    else
        rm -f "$REAL_HOME/.config/systemd/user/$AGENT_SERVICE" \
            && success "Removed $REAL_HOME/.config/systemd/user/$AGENT_SERVICE" || true
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
    "/var/log/spore-os"
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
