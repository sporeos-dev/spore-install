#!/usr/bin/env bash
# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# build.sh — Spore OS Linux CI/CD build script
# Compiles all binaries for amd64 and arm64 and stages them in dist/.
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

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
RELEASE_MODE=false
for arg in "$@"; do
    if [[ "$arg" == "release" ]]; then
        RELEASE_MODE=true
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"

NODES=(spore-shell spore-witness spore-log spore)
ARCHS=(amd64 arm64)

# ---------------------------------------------------------------------------
# Prepare dist/ layout
# ---------------------------------------------------------------------------
step "Preparing dist/ directory"
rm -rf "$DIST_DIR"
for arch in "${ARCHS[@]}"; do
    mkdir -p "$DIST_DIR/$arch/bin"
done
mkdir -p "$DIST_DIR/nodes"
success "dist/ created at $DIST_DIR"

# ---------------------------------------------------------------------------
# Helper: build a Linux binary for a specific architecture
# Must be called from within the Go project directory.
# Usage: build_linux <output-base-name>
# ---------------------------------------------------------------------------
build_linux() {
    local base_name="$1"
    for arch in "${ARCHS[@]}"; do
        echo "    Building $arch..."
        GOOS=linux GOARCH="$arch" go build -o "${base_name}_${arch}" .
    done
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
    build_linux spored
    for arch in "${ARCHS[@]}"; do
        mv "spored_${arch}" "$DIST_DIR/$arch/spored"
    done
    cp spored.manifest.spore.yaml    "$DIST_DIR/spored.manifest.spore.yaml"
)
success "spored → dist/{amd64,arm64}/spored"

# ---------------------------------------------------------------------------
# 2. Build CLI nodes
# ---------------------------------------------------------------------------
step "Building CLI nodes"

for node in "${NODES[@]}"; do
    echo "  ▸ $node"
    NODE_DIR="$DEV/spore-core-nodes/$node"
    [[ -d "$NODE_DIR" ]] || die "Node source not found at $NODE_DIR"

    (
        cd "$NODE_DIR"
        go test ./... -count=1 || die "$node tests failed — aborting build"
        build_linux "$node"
        for arch in "${ARCHS[@]}"; do
            mv "${node}_${arch}" "$DIST_DIR/$arch/bin/$node"
        done
        cp "${node}.manifest.spore.yaml"    "$DIST_DIR/nodes/${node}.manifest.spore.yaml"
    )
    success "$node → dist/{amd64,arm64}/bin/$node"
done

# ---------------------------------------------------------------------------
# 3. Stage installer scripts
# ---------------------------------------------------------------------------
step "Staging installer scripts"
cp "$SCRIPT_DIR/install.sh" "$DIST_DIR/install.sh"
cp "$SCRIPT_DIR/uninstall.sh" "$DIST_DIR/uninstall.sh"
success "Staged install.sh and uninstall.sh to dist/"

# ---------------------------------------------------------------------------
# 4. Generate SHA-256 checksums
# ---------------------------------------------------------------------------
step "Generating SHA-256 checksums"
(
    cd "$DIST_DIR"
    find . -type f ! -name "checksums.sha256" ! -name "install.sh" ! -name "uninstall.sh" | sort | while read -r file; do
        sha256sum "$file" | sed 's/  \.\//  /'
    done > checksums.sha256
)
success "SHA-256 checksums written to dist/checksums.sha256"

# ---------------------------------------------------------------------------
# 5. Package release archive (if requested)
# ---------------------------------------------------------------------------
if [[ "$RELEASE_MODE" == "true" ]]; then
    step "Packaging release archive"
    tar -czf "$REPO_ROOT/spore-os-install-linux.tar.gz" -C "$REPO_ROOT" dist
    success "Release archive created: spore-os-install-linux.tar.gz"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo -e "\n${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  Linux build complete!${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
