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
    CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 go build -o "${out_name}_arm64" .
    echo "    Building amd64..."
    CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 \
        CC="clang -arch x86_64" CXX="clang++ -arch x86_64" \
        go build -o "${out_name}_amd64" .
    echo "    Linking universal binary..."
    lipo -create "${out_name}_arm64" "${out_name}_amd64" -output "${out_name}"
    rm -f "${out_name}_arm64" "${out_name}_amd64"
}

# ---------------------------------------------------------------------------
# Helper: build spore-client-libs C libraries as fat (arm64 + x86_64).
# Compiles both slices fresh from source so this step is always idempotent.
# Usage: make_fat_client_libs <client-libs-root>
# ---------------------------------------------------------------------------
make_fat_client_libs() {
    local root="$1"
    local dist="$root/dist"

    echo "    Building parser (arm64 + x86_64)..."
    (
        cd "$root/parser"
        local arm_objs=() x86_objs=()
        for src in source/*.cpp; do
            clang++ -std=c++17 -arch arm64  -Iinclude -Isource -O2 -DNDEBUG -c "$src" -o "${src%.cpp}_arm.o"
            clang++ -std=c++17 -arch x86_64 -Iinclude -Isource -O2 -DNDEBUG -c "$src" -o "${src%.cpp}_x86.o"
            arm_objs+=("${src%.cpp}_arm.o")
            x86_objs+=("${src%.cpp}_x86.o")
        done
        ar rcs "$dist/libspore_parser_arm.a" "${arm_objs[@]}"
        ar rcs "$dist/libspore_parser_x86.a" "${x86_objs[@]}"
        rm -f "${arm_objs[@]}" "${x86_objs[@]}"
    )
    lipo -create "$dist/libspore_parser_arm.a" "$dist/libspore_parser_x86.a" \
         -output "$dist/libspore_parser.a"
    rm -f "$dist/libspore_parser_arm.a" "$dist/libspore_parser_x86.a"

    echo "    Building spore_c (arm64 + x86_64)..."
    (
        cd "$root/spore_c"
        local arm_objs=() x86_objs=()
        for src in source/*.cpp; do
            clang++ -std=c++17 -arch arm64  -fPIC -Iinclude -Isource -I../parser/include -O2 -DNDEBUG -c "$src" -o "${src%.cpp}_arm.o"
            clang++ -std=c++17 -arch x86_64 -fPIC -Iinclude -Isource -I../parser/include -O2 -DNDEBUG -c "$src" -o "${src%.cpp}_x86.o"
            arm_objs+=("${src%.cpp}_arm.o")
            x86_objs+=("${src%.cpp}_x86.o")
        done
        ar rcs "$dist/libspore_c_arm.a" "${arm_objs[@]}"
        ar rcs "$dist/libspore_c_x86.a" "${x86_objs[@]}"
        rm -f "${arm_objs[@]}" "${x86_objs[@]}"
    )
    lipo -create "$dist/libspore_c_arm.a" "$dist/libspore_c_x86.a" \
         -output "$dist/libspore_c.a"
    rm -f "$dist/libspore_c_arm.a" "$dist/libspore_c_x86.a"

    # Remove any dylibs so the Go linker uses only the static archives.
    rm -f "$dist"/*.dylib
}

# ---------------------------------------------------------------------------
# 0. Run centralized quick checks
# ---------------------------------------------------------------------------
step "Running centralized quick checks"

RELEASES_DIR="$DEV/spore-os-releases"
[[ -d "$RELEASES_DIR" ]] || die "spore-os-releases not found at $RELEASES_DIR"

if ! python3 "$RELEASES_DIR/automation/spore-quick/main.py"; then
    warn "Quick checks failed — continuing build"
fi

CLIENT_LIBS_DIR="$DEV/spore-client-libs"
[[ -d "$CLIENT_LIBS_DIR" ]] || die "spore-client-libs not found at $CLIENT_LIBS_DIR"

step "Making spore-client-libs fat (arm64 + x86_64)"
make_fat_client_libs "$CLIENT_LIBS_DIR"
success "spore-client-libs built"

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
    NODE_DIR="$DEV/spore-core-nodes/$node"
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
# 2b. Build spore-dialog node
# ---------------------------------------------------------------------------
step "Building spore-dialog node"

DIALOG_DIR="$DEV/spore-dialog/spore-dialog"
[[ -d "$DIALOG_DIR" ]] || die "spore-dialog source not found at $DIALOG_DIR"

(
    cd "$DIALOG_DIR"
    echo "  Running tests..."
    go test ./... -count=1 || die "spore-dialog tests failed — aborting build"
    build_universal spore-dialog
    cp spore-dialog                          "$DIST_DIR/bin/spore-dialog"
    cp spore-dialog.manifest.spore.yaml      "$DIST_DIR/nodes/spore-dialog.manifest.spore.yaml"
    rm -f spore-dialog
)
success "spore-dialog → dist/bin/spore-dialog"

# ---------------------------------------------------------------------------
# 2c. Build hyphae user agent
# ---------------------------------------------------------------------------
step "Building hyphae user agent"

HYPHAE_DIR="$DEV/spore-hyphae/hyphae"
[[ -d "$HYPHAE_DIR" ]] || die "hyphae source not found at $HYPHAE_DIR"

(
    cd "$HYPHAE_DIR"
    echo "  Running tests..."
    go test ./... -count=1 || die "hyphae tests failed — aborting build"
    build_universal hyphae
    cp hyphae                           "$DIST_DIR/bin/hyphae"
    cp hyphae.manifest.spore.yaml       "$DIST_DIR/nodes/hyphae.manifest.spore.yaml"
    rm -f hyphae
)
success "hyphae → dist/bin/hyphae"

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
        shasum -a 256 spored.manifest.spore.yaml
        for f in bin/*; do
            [[ -f "$f" ]] && shasum -a 256 "$f"
        done
        for f in nodes/*; do
            [[ -f "$f" ]] && shasum -a 256 "$f"
        done
    } | tee checksums.sha256
)
success "checksums.sha256 written"

# ---------------------------------------------------------------------------
# 5. Package release archive (if requested)
# ---------------------------------------------------------------------------
if [[ "$RELEASE_MODE" == "true" ]]; then
    step "Packaging release archive"
    tar -czf "$REPO_ROOT/spore-os-install-macos.tar.gz" -C "$REPO_ROOT" dist
    success "Release archive created: spore-os-install-macos.tar.gz"
fi

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
