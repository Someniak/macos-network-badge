# Network Badge - macOS Menu Bar Network Monitor

## Project Overview
A native macOS menu bar app (Swift/SwiftUI) that shows live network latency
and connection type. Built for travellers who want to monitor their internet
quality on trains, cafés, etc.

## Build Commands
```bash
# Build (debug)
swift build

# Build (release)
swift build -c release

# Run locally (after building)
swift run NetworkBadge

# Build .app bundle
./scripts/build-app.sh

# Create DMG for distribution
./scripts/create-dmg.sh
```

## Test Commands
```bash
# Run all tests
swift test

# Run a specific test class
swift test --filter NetworkBadgeTests.ConnectionInfoTests

# Run with verbose output
swift test --verbose
```

## Lint / Format
```bash
# If swiftlint is installed
swiftlint lint Sources/ Tests/

# If swift-format is installed
swift-format lint --recursive Sources/ Tests/
```

## Architecture
- **SwiftUI MenuBarExtra** — the menu bar presence (macOS 13+)
- **NWPathMonitor** — detects network interface type (WiFi, Ethernet, etc.)
- **CoreWLAN** — reads WiFi SSID and signal info
- **URLSession** — measures HTTP latency to detect real internet quality
- **@Observable pattern** — reactive data flow from monitors → UI

## Key Files
- `Sources/NetworkBadge/NetworkBadgeApp.swift` — App entry point, MenuBarExtra setup
- `Sources/NetworkBadge/Monitors/NetworkMonitor.swift` — Network type detection
- `Sources/NetworkBadge/Monitors/LatencyMonitor.swift` — Latency measurement
- `Sources/NetworkBadge/Views/MenuBarView.swift` — Popover UI
- `Sources/NetworkBadge/Models/ConnectionInfo.swift` — Data models
- `Tests/NetworkBadgeTests/` — Unit tests

## Platform
- macOS 13+ (Ventura) required for MenuBarExtra
- Swift 5.9+
- No external dependencies — uses only Apple frameworks
