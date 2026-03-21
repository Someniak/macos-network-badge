#!/bin/bash
# ---------------------------------------------------------
# build-ios.sh — Build the iOS app
#
# Builds the NetworkBadge iOS app for simulator or device.
# Requires Xcode 15+ with iOS 16+ SDK.
#
# Usage:
#   ./scripts/build-ios.sh              # Build for simulator
#   ./scripts/build-ios.sh device       # Build for device
#   ./scripts/build-ios.sh clean        # Clean build artifacts
# ---------------------------------------------------------

set -euo pipefail

SCHEME="NetworkBadge"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/ios"

cd "$PROJECT_DIR"

case "${1:-simulator}" in
    simulator)
        echo "Building for iOS Simulator..."
        xcodebuild build \
            -scheme "$SCHEME" \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            -derivedDataPath "$BUILD_DIR" \
            CODE_SIGNING_ALLOWED=NO \
            2>&1 | tail -20
        echo "Build complete. App at: $BUILD_DIR"
        ;;
    device)
        echo "Building for iOS device..."
        xcodebuild build \
            -scheme "$SCHEME" \
            -destination 'generic/platform=iOS' \
            -derivedDataPath "$BUILD_DIR" \
            2>&1 | tail -20
        echo "Build complete."
        ;;
    clean)
        echo "Cleaning iOS build artifacts..."
        rm -rf "$BUILD_DIR"
        echo "Clean complete."
        ;;
    *)
        echo "Usage: $0 [simulator|device|clean]"
        exit 1
        ;;
esac
