#!/bin/bash
# ---------------------------------------------------------
# build-app.sh — Build NetworkBadge.app from source
#
# This script:
#   1. Compiles the Swift code in release mode
#   2. Creates a proper macOS .app bundle directory structure
#   3. Copies the binary and Info.plist into the bundle
#   4. Optionally code-signs the app (for distribution)
#
# Usage:
#   ./scripts/build-app.sh
#
# Output:
#   build/NetworkBadge.app
# ---------------------------------------------------------

set -euo pipefail  # Exit on any error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'  # No Color

echo -e "${GREEN}=== Building Network Badge ===${NC}"

# ── Step 1: Compile in release mode ──────────────────────
echo -e "${YELLOW}Compiling Swift code (release mode)...${NC}"
swift build -c release

# Find the compiled binary
# Swift Package Manager puts it in .build/release/
BINARY_PATH=".build/release/NetworkBadge"
if [ ! -f "$BINARY_PATH" ]; then
    echo -e "${RED}Error: Binary not found at $BINARY_PATH${NC}"
    echo "Make sure 'swift build -c release' completed successfully."
    exit 1
fi

echo -e "${GREEN}Compilation successful!${NC}"

# ── Step 2: Create .app bundle structure ─────────────────
# macOS .app bundles are just directories with a specific structure:
#
#   NetworkBadge.app/
#     Contents/
#       Info.plist          ← App metadata
#       MacOS/
#         NetworkBadge      ← The actual binary
#       Resources/          ← Icons, assets (optional)

APP_DIR="build/NetworkBadge.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo -e "${YELLOW}Creating .app bundle...${NC}"

# Clean previous build
rm -rf "$APP_DIR"

# Create directory structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# ── Step 3: Copy files into bundle ───────────────────────
echo -e "${YELLOW}Copying binary and resources...${NC}"

# Copy the compiled binary
cp "$BINARY_PATH" "$MACOS_DIR/NetworkBadge"

# Make it executable
chmod +x "$MACOS_DIR/NetworkBadge"

# Copy Info.plist (tells macOS about our app)
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

# ── Step 4: Optional code signing ────────────────────────
# Code signing is required for:
#   - App Store distribution
#   - Gatekeeper (macOS security) approval
#   - Notarization
#
# For local development, you can skip this.
# For distribution, you need an Apple Developer account.

if [ "${CODESIGN:-}" = "1" ]; then
    IDENTITY="${CODESIGN_IDENTITY:-"-"}"  # "-" means ad-hoc signing
    echo -e "${YELLOW}Code signing with identity: $IDENTITY${NC}"
    codesign --force --deep --sign "$IDENTITY" "$APP_DIR"
    echo -e "${GREEN}Code signing complete!${NC}"
else
    echo -e "${YELLOW}Skipping code signing (set CODESIGN=1 to enable)${NC}"
fi

# ── Done! ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}=== Build complete! ===${NC}"
echo -e "App bundle: ${GREEN}$APP_DIR${NC}"
echo ""
echo "To run the app:"
echo "  open $APP_DIR"
echo ""
echo "To code sign for distribution:"
echo "  CODESIGN=1 CODESIGN_IDENTITY=\"Developer ID Application: Your Name\" ./scripts/build-app.sh"
