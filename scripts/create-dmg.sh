#!/bin/bash
# ---------------------------------------------------------
# create-dmg.sh — Package NetworkBadge.app into a .dmg file
#
# A DMG (Disk Image) is the standard way to distribute
# macOS apps outside the App Store. When users open the DMG,
# they see the app and can drag it to Applications.
#
# This script:
#   1. Builds the .app bundle (if not already built)
#   2. Creates a temporary DMG with the app inside
#   3. Converts it to a compressed, read-only DMG
#
# Usage:
#   ./scripts/create-dmg.sh
#
# Output:
#   build/NetworkBadge.dmg
# ---------------------------------------------------------

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

APP_DIR="build/NetworkBadge.app"
DMG_NAME="NetworkBadge"
DMG_OUTPUT="build/${DMG_NAME}.dmg"
DMG_TEMP="build/${DMG_NAME}-temp.dmg"
VOLUME_NAME="Network Badge"
DMG_SIZE="50m"  # 50 MB should be plenty

echo -e "${GREEN}=== Creating DMG ===${NC}"

# ── Step 1: Make sure the .app exists ────────────────────
if [ ! -d "$APP_DIR" ]; then
    echo -e "${YELLOW}.app not found, building first...${NC}"
    ./scripts/build-app.sh
fi

# Verify it exists now
if [ ! -d "$APP_DIR" ]; then
    echo -e "${RED}Error: Failed to build .app bundle${NC}"
    exit 1
fi

# ── Step 2: Clean up any previous DMG ───────────────────
rm -f "$DMG_OUTPUT"
rm -f "$DMG_TEMP"

# ── Step 3: Create temporary DMG ─────────────────────────
echo -e "${YELLOW}Creating disk image...${NC}"

# Create a temporary read/write DMG
hdiutil create \
    -srcfolder "$APP_DIR" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size "$DMG_SIZE" \
    "$DMG_TEMP"

# ── Step 4: Mount and customize (add Applications symlink) ──
echo -e "${YELLOW}Customizing disk image...${NC}"

# Mount the temporary DMG
MOUNT_DIR=$(hdiutil attach -readwrite -noverify "$DMG_TEMP" | \
    grep -E '^\S+\s+Apple_HFS' | \
    sed 's/.*Apple_HFS\s*//')

if [ -z "$MOUNT_DIR" ]; then
    echo -e "${RED}Error: Failed to mount DMG${NC}"
    exit 1
fi

# Add a symbolic link to /Applications
# This lets users drag the app to Applications easily
ln -sf /Applications "$MOUNT_DIR/Applications"

# Unmount
sync
hdiutil detach "$MOUNT_DIR"

# ── Step 5: Convert to compressed read-only DMG ─────────
echo -e "${YELLOW}Compressing disk image...${NC}"

hdiutil convert \
    "$DMG_TEMP" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_OUTPUT"

# Clean up temporary DMG
rm -f "$DMG_TEMP"

# ── Done! ────────────────────────────────────────────────
DMG_SIZE_ACTUAL=$(du -h "$DMG_OUTPUT" | cut -f1)

echo ""
echo -e "${GREEN}=== DMG created! ===${NC}"
echo -e "File: ${GREEN}$DMG_OUTPUT${NC}"
echo -e "Size: ${GREEN}$DMG_SIZE_ACTUAL${NC}"
echo ""
echo "To test: open $DMG_OUTPUT"
