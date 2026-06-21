#!/usr/bin/env bash
# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# startdev.sh — Start Spore OS local development environment on Linux

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

# Validate environment
[[ -n "${DEV:-}" ]] || die "DEV environment variable is not set. Aborting."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export SPORE_DATA_DIR="$REPO_ROOT/dev"
SOCKET_PATH="/tmp/spore2.sock"

# Verify build has been run
[[ -f "$SPORE_DATA_DIR/spored" ]] || die "spored binary not found in $SPORE_DATA_DIR. Run './linux/develop.sh' first!"

# Ensure directories exist
mkdir -p "$SPORE_DATA_DIR/data" "$SPORE_DATA_DIR/manifests" "$SPORE_DATA_DIR/run"

# Stop any previously running dev daemon or nodes using this socket
rm -f "$SOCKET_PATH"

# Install development node manifests offline
step "Installing development node manifests"
shopt -s nullglob
manifests=("$SPORE_DATA_DIR/nodes/"*.manifest.spore.yaml)
shopt -u nullglob

if [[ ${#manifests[@]} -eq 0 ]]; then
    warn "No manifests found in $SPORE_DATA_DIR/nodes/"
else
    for manifest in "${manifests[@]}"; do
        "$SPORE_DATA_DIR/spored" install "$manifest"
        success "Installed: $(basename "$manifest")"
    done
fi

# Start spored
step "Starting spored on $SOCKET_PATH..."
"$SPORE_DATA_DIR/spored" "$SOCKET_PATH" &
SPORED_PID=$!

# Wait for socket to appear
success "Waiting for daemon socket to be created..."
for _ in {1..30}; do
    if [[ -S "$SOCKET_PATH" ]]; then
        break
    fi
    sleep 0.1
done

if [[ ! -S "$SOCKET_PATH" ]]; then
    kill "$SPORED_PID" 2>/dev/null || true
    die "Daemon failed to start or create socket at $SOCKET_PATH"
fi
success "Daemon is listening!"

# Start core logging background nodes
step "Starting core nodes..."

# spore-log runs in background
"$SPORE_DATA_DIR/bin/spore-log" "$SOCKET_PATH" &
LOG_PID=$!
success "Started spore-log (PID $LOG_PID)"

# spore-witness runs in background
"$SPORE_DATA_DIR/bin/spore-witness" "$SOCKET_PATH" &
WITNESS_PID=$!
success "Started spore-witness (PID $WITNESS_PID)"

# Define cleanup function
cleanup() {
    echo ""
    step "Shutting down development environment..."
    kill "$WITNESS_PID" 2>/dev/null || true
    kill "$LOG_PID" 2>/dev/null || true
    kill "$SPORED_PID" 2>/dev/null || true
    rm -f "$SOCKET_PATH"
    success "All processes stopped. Cleaned up $SOCKET_PATH."
}

# Setup trap to clean up on exit
trap cleanup EXIT INT TERM

echo -e "\n${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  Development environment is running!${NC}"
echo -e "${GREEN}${BOLD}  Press Ctrl+C to stop all processes.${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Try running spore or spore-shell in another terminal:${NC}"
echo -e "  export DEV=\$DEV"
echo -e "  $SPORE_DATA_DIR/bin/spore-shell $SOCKET_PATH"
echo ""

# Wait in foreground
while kill -0 "$SPORED_PID" 2>/dev/null; do
    sleep 1
done
