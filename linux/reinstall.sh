#!/usr/bin/env bash
# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# reinstall.sh — Spore OS Linux development reinstall helper
# Uninstalls, cleans native client-library artifacts, rebuilds, and reinstalls.
# Run as a regular user; this script invokes sudo only for installation steps.

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
# Preserve the invoking user's environment for the build and Hyphae install.
# ---------------------------------------------------------------------------
[[ "$EUID" -ne 0 ]] || die "reinstall.sh must be run as yourself, not sudo. Re-run: ./linux/reinstall.sh"
[[ -n "${DEV:-}" ]] || die "DEV environment variable is not set. Aborting."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
CLIENT_LIBS_DIST="$DEV/spore-client-libs/dist"

# ---------------------------------------------------------------------------
# 1. Uninstall — auto-confirm because this script is explicitly a reinstall.
# Use the source script because dist/ is rebuilt next.
# ---------------------------------------------------------------------------
step "Uninstalling current installation"

if [[ -x "$SCRIPT_DIR/uninstall.sh" ]]; then
    echo "yes" | sudo bash "$SCRIPT_DIR/uninstall.sh"
else
    warn "linux/uninstall.sh not found — skipping uninstall"
fi

# ---------------------------------------------------------------------------
# 2. Clean native libraries so the C/C++ archives rebuild from source.
# ---------------------------------------------------------------------------
step "Cleaning spore-client-libs/dist"

if [[ -d "$CLIENT_LIBS_DIST" ]]; then
    rm -rf "$CLIENT_LIBS_DIST"
    success "Removed $CLIENT_LIBS_DIST"
else
    warn "$CLIENT_LIBS_DIST not found — nothing to clean"
fi

# ---------------------------------------------------------------------------
# 3. Build as the invoking user.
# ---------------------------------------------------------------------------
step "Building"
bash "$SCRIPT_DIR/build.sh"

# ---------------------------------------------------------------------------
# 4. Install the freshly staged release.
# ---------------------------------------------------------------------------
step "Installing"
sudo bash "$DIST_DIR/install.sh"

echo -e "\n${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  Reinstall complete!${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
