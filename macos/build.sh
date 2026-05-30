#!/usr/bin/env bash
# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# build.sh — Spore OS macOS CI/CD build script
# Compiles all binaries as universal (arm64 + amd64) and stages them in dist/.
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
DIST_DIR="$REPO_ROOT/dist"

NODES=(spore-shell spore-witness spore-log spore-dialog spore)

# ---------------------------------------------------------------------------
# Prepare dist/ layout
# ---------------------------------------------------------------------------
step "Preparing dist/ directory"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/bin" "$DIST_DIR/nodes"
success "dist/ created at $DIST_DIR"

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
step "Building spored daemon"

SPORED_DIR="$DEV/spore-os/spored"
[[ -d "$SPORED_DIR" ]] || die "spored source not found at $SPORED_DIR"

(
    cd "$SPORED_DIR"
    echo "  Running tests..."
    go test ./... -count=1 || die "spored tests failed — aborting build"
    build_universal spored
    cp spored                        "$DIST_DIR/spored"
    cp spored.manifest.spore.yaml    "$DIST_DIR/spored.manifest.spore.yaml"
    rm -f spored
)
success "spored → dist/spored"

# ---------------------------------------------------------------------------
# 2. Build CLI nodes
# ---------------------------------------------------------------------------
step "Building CLI nodes"

for node in "${NODES[@]}"; do
    echo "  ▸ $node"
    NODE_DIR="$DEV/spore-cli/$node"
    [[ -d "$NODE_DIR" ]] || die "Node source not found at $NODE_DIR"

    (
        cd "$NODE_DIR"
        go test ./... -count=1 || die "$node tests failed — aborting build"
        build_universal "$node"
        cp "$node"                          "$DIST_DIR/bin/$node"
        cp "${node}.manifest.spore.yaml"    "$DIST_DIR/nodes/${node}.manifest.spore.yaml"
        rm -f "$node"
    )
    success "$node → dist/bin/$node"
done

# ---------------------------------------------------------------------------
# 3. Stage installer scripts
# ---------------------------------------------------------------------------
step "Staging installer scripts"
cp "$SCRIPT_DIR/install.sh"   "$DIST_DIR/install.sh"
cp "$SCRIPT_DIR/uninstall.sh" "$DIST_DIR/uninstall.sh"
chmod +x "$DIST_DIR/install.sh" "$DIST_DIR/uninstall.sh"
success "install.sh and uninstall.sh → dist/"

# ---------------------------------------------------------------------------
# 4. Write SHA-256 checksums for all binaries
# ---------------------------------------------------------------------------
step "Computing SHA-256 checksums"
(
    cd "$DIST_DIR"
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
echo -e "${GREEN}${BOLD}  Build complete!  dist/ contents:${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
find "$DIST_DIR" ! -type d | sort | sed "s|${DIST_DIR}/||" | while IFS= read -r f; do
    echo -e "  ${GREEN}${f}${NC}"
done
echo ""
