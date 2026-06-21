#!/usr/bin/env bash
# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# develop.sh — Spore OS macOS development build script
# Compiles all binaries with isDev=true, stages them in dev/.
# Does NOT require sudo. Requires the DEV environment variable to be set.

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
# Validate environment
# ---------------------------------------------------------------------------
[[ -n "${DEV:-}" ]] || die "DEV environment variable is not set. Aborting."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEV_DIR="$REPO_ROOT/dev"

NODES=(spore-shell spore-witness spore-log spore)

CLIENT_GO="$DEV/spore-client-libs/go/client.go"
SPORED_MAIN_GO="$DEV/spore-os/spored/main.go"

# ---------------------------------------------------------------------------
# Helper: temporarily enable/disable isDev in third party & daemon repos
# ---------------------------------------------------------------------------
enable_isdev() {
    step "Setting isDev=true in source files prior to build"
    [[ -f "$CLIENT_GO" ]] || die "client.go not found at $CLIENT_GO"
    [[ -f "$SPORED_MAIN_GO" ]] || die "main.go not found at $SPORED_MAIN_GO"

    python3 -c "
import sys
for path in [sys.argv[1], sys.argv[2]]:
    with open(path, 'r') as f:
        content = f.read()
    content = content.replace('const isDev = false', 'const isDev = true')
    with open(path, 'w') as f:
        f.write(content)
" "$CLIENT_GO" "$SPORED_MAIN_GO"
    success "isDev=true set in client.go and main.go"
}

disable_isdev() {
    step "Restoring isDev=false in source files"
    if [[ -f "$CLIENT_GO" ]] && [[ -f "$SPORED_MAIN_GO" ]]; then
        python3 -c "
import sys
for path in [sys.argv[1], sys.argv[2]]:
    with open(path, 'r') as f:
        content = f.read()
    content = content.replace('const isDev = true', 'const isDev = false')
    with open(path, 'w') as f:
        f.write(content)
" "$CLIENT_GO" "$SPORED_MAIN_GO"
        success "isDev=false restored in source files"
    fi
}

# Ensure isDev is restored even on script failure
trap disable_isdev EXIT
enable_isdev

# ---------------------------------------------------------------------------
# Prepare dev/ layout
# ---------------------------------------------------------------------------
step "Preparing dev/ directory"
rm -rf "$DEV_DIR"
mkdir -p "$DEV_DIR/bin" "$DEV_DIR/nodes"
success "dev/ created at $DEV_DIR"

# ---------------------------------------------------------------------------
# Helper: build a universal macOS binary via lipo
# Must be called from within the Go project directory.
# Usage: build_universal <output-binary-name>
# ---------------------------------------------------------------------------
build_universal() {
    local out_name="$1"
    echo "    Building arm64..."
    GOOS=darwin GOARCH=arm64 go build -o "${out_name}_arm64" .
    echo "    Building amd64..."
    GOOS=darwin GOARCH=amd64 go build -o "${out_name}_amd64" .
    echo "    Linking universal binary..."
    lipo -create "${out_name}_arm64" "${out_name}_amd64" -output "${out_name}"
    rm -f "${out_name}_arm64" "${out_name}_amd64"
}

# ---------------------------------------------------------------------------
# 1. Build spored daemon
# ---------------------------------------------------------------------------
step "Building spored daemon for development"

SPORED_DIR="$DEV/spore-os/spored"
[[ -d "$SPORED_DIR" ]] || die "spored source not found at $SPORED_DIR"

(
    cd "$SPORED_DIR"
    echo "  Running tests..."
    go test ./... -count=1 || die "spored tests failed — aborting build"
    build_universal spored
    cp spored                        "$DEV_DIR/spored"
    cp spored.manifest.spore.yaml    "$DEV_DIR/spored.manifest.spore.yaml"
    rm -f spored
)
success "spored → dev/spored"

# ---------------------------------------------------------------------------
# 2. Build CLI nodes
# ---------------------------------------------------------------------------
step "Building CLI nodes for development"

for node in "${NODES[@]}"; do
    echo "  ▸ $node"
    NODE_DIR="$DEV/spore-core-nodes/$node"
    [[ -d "$NODE_DIR" ]] || die "Node source not found at $NODE_DIR"

    (
        cd "$NODE_DIR"
        go test ./... -count=1 || die "$node tests failed — aborting build"
        build_universal "$node"
        cp "$node"                          "$DEV_DIR/bin/$node"
        cp "${node}.manifest.spore.yaml"    "$DEV_DIR/nodes/${node}.manifest.spore.yaml"
        rm -f "$node"
    )
    success "$node → dev/bin/$node"
done

# ---------------------------------------------------------------------------
# 3. Write SHA-256 checksums for all binaries
# ---------------------------------------------------------------------------
step "Computing SHA-256 checksums"
(
    cd "$DEV_DIR"
    {
        shasum -a 256 spored
        for f in bin/*; do
            [[ -f "$f" ]] && shasum -a 256 "$f"
        done
    } | tee checksums.sha256
)
success "checksums.sha256 written"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo -e "\n${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  Development Build complete!  dev/ contents:${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
find "$DEV_DIR" ! -type d | sort | sed "s|${DEV_DIR}/||" | while IFS= read -r f; do
    echo -e "  ${GREEN}${f}${NC}"
done
echo ""
