#!/usr/bin/env bash
# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# reinstall.sh — Spore OS macOS dev reinstall helper
# Uninstalls, cleans spore-client-libs/dist, rebuilds, and reinstalls.
# Must be run with sudo.

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
# Must NOT be root — sudo is invoked internally so $DEV and user env are intact
# ---------------------------------------------------------------------------
[[ "$EUID" -ne 0 ]] || die "reinstall.sh must be run as yourself, not sudo.  Re-run: ./reinstall.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"

CLIENT_LIBS_DIST="$(cd "$REPO_ROOT/.." && pwd)/spore-client-libs/dist"

# ---------------------------------------------------------------------------
# 1. Uninstall — auto-confirm since this script is explicitly for reinstalling
# ---------------------------------------------------------------------------
step "Uninstalling current installation"

if [[ -x "$DIST_DIR/uninstall.sh" ]]; then
    echo "yes" | sudo bash "$DIST_DIR/uninstall.sh"
else
    warn "dist/uninstall.sh not found — skipping uninstall"
fi

# ---------------------------------------------------------------------------
# 2. Clean spore-client-libs/dist so C/C++ libraries rebuild from scratch
# ---------------------------------------------------------------------------
step "Cleaning spore-client-libs/dist"

if [[ -d "$CLIENT_LIBS_DIST" ]]; then
    rm -rf "$CLIENT_LIBS_DIST"
    success "Removed $CLIENT_LIBS_DIST"
else
    warn "$CLIENT_LIBS_DIST not found — nothing to clean"
fi

# ---------------------------------------------------------------------------
# 3. Build (no sudo — preserves $DEV and user environment)
# ---------------------------------------------------------------------------
step "Building"
bash "$SCRIPT_DIR/build.sh"

# ---------------------------------------------------------------------------
# 4. Install from the freshly staged dist/
# ---------------------------------------------------------------------------
step "Installing"
sudo bash "$DIST_DIR/install.sh"

echo -e "\n${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  Reinstall complete!${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
