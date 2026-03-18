#!/bin/bash
# ---------------------------------------------------------
# install.sh — Build and install NetworkBadge.app
#
# This script:
#   1. Builds the .app bundle (via build-app.sh)
#   2. Copies it to /Applications/
#   3. Optionally launches the app
#
# Usage:
#   ./scripts/install.sh
# ---------------------------------------------------------

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$PROJECT_DIR/build/NetworkBadge.app"
INSTALL_DIR="/Applications"

# ── Step 1: Build the .app bundle ─────────────────────────
echo -e "${YELLOW}Building NetworkBadge.app...${NC}"
"$SCRIPT_DIR/build-app.sh"

if [ ! -d "$APP_BUNDLE" ]; then
    echo -e "${RED}Error: App bundle not found at $APP_BUNDLE${NC}"
    exit 1
fi

# ── Step 2: Copy to /Applications ─────────────────────────
echo ""
echo -e "${YELLOW}Installing to $INSTALL_DIR...${NC}"

# Remove previous installation if it exists
if [ -d "$INSTALL_DIR/NetworkBadge.app" ]; then
    echo -e "${YELLOW}Removing previous installation...${NC}"
    rm -rf "$INSTALL_DIR/NetworkBadge.app"
fi

cp -R "$APP_BUNDLE" "$INSTALL_DIR/NetworkBadge.app"
echo -e "${GREEN}Installed to $INSTALL_DIR/NetworkBadge.app${NC}"

# ── Step 3: Launch the app ────────────────────────────────
echo ""
read -p "Launch NetworkBadge now? [Y/n] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    open "$INSTALL_DIR/NetworkBadge.app"
    echo -e "${GREEN}NetworkBadge is running!${NC}"
fi

echo ""
echo -e "${GREEN}=== Installation complete! ===${NC}"
echo ""
echo "To enable auto-launch at login:"
echo "  Click the menu bar icon → toggle \"Launch at Login\""
echo ""
echo "To uninstall:"
echo "  rm -rf $INSTALL_DIR/NetworkBadge.app"
