#!/bin/bash
# ---------------------------------------------------------
# build-ios.sh — Build the iOS app
#
# Generates an Xcode project via XcodeGen (if needed) and
# builds the NetworkBadge iOS app for simulator or device.
# Requires Xcode 15+ with iOS 16+ SDK and XcodeGen.
#
# Install XcodeGen:  brew install xcodegen
#
# Usage:
#   ./scripts/build-ios.sh              # Build for simulator
#   ./scripts/build-ios.sh device       # Build for device
#   ./scripts/build-ios.sh clean        # Clean build artifacts
# ---------------------------------------------------------

set -euo pipefail

SCHEME="NetworkBadgeIOS"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/ios"
XCODEPROJ="$PROJECT_DIR/NetworkBadge.xcodeproj"

cd "$PROJECT_DIR"

# Generate Xcode project if missing or project.yml is newer
generate_project() {
    if ! command -v xcodegen &> /dev/null; then
        echo "Error: XcodeGen not found. Install with: brew install xcodegen"
        exit 1
    fi

    if [ ! -d "$XCODEPROJ" ] || [ "project.yml" -nt "$XCODEPROJ" ]; then
        echo "Generating Xcode project from project.yml..."
        xcodegen generate
        echo "Generated $XCODEPROJ"
    fi
}

case "${1:-simulator}" in
    simulator)
        generate_project
        echo "Building for iOS Simulator..."
        xcodebuild build \
            -project "$XCODEPROJ" \
            -scheme "$SCHEME" \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            -derivedDataPath "$BUILD_DIR" \
            CODE_SIGNING_ALLOWED=NO \
            2>&1 | tail -20
        echo "Build complete. App at: $BUILD_DIR"
        ;;
    device)
        generate_project
        echo "Building for iOS device..."
        xcodebuild build \
            -project "$XCODEPROJ" \
            -scheme "$SCHEME" \
            -destination 'generic/platform=iOS' \
            -derivedDataPath "$BUILD_DIR" \
            2>&1 | tail -20
        echo "Build complete."
        ;;
    clean)
        echo "Cleaning iOS build artifacts..."
        rm -rf "$BUILD_DIR"
        rm -rf "$XCODEPROJ"
        echo "Clean complete."
        ;;
    *)
        echo "Usage: $0 [simulator|device|clean]"
        exit 1
        ;;
esac
