# Network Badge

A native macOS menu bar app that shows **live internet latency** and **connection type** at a glance. Built for travellers who want to monitor their internet quality on trains, in cafes, or wherever they roam.

## Screenshots
<img width="297" height="277" alt="image" src="https://github.com/user-attachments/assets/e5276b4b-1d09-4c10-8d96-387403383ed4" />

## What It Does

- Shows real-time ping latency in the menu bar (e.g. `42ms`)
- Detects your connection type: **WiFi**, **Ethernet**, **USB Tethering**, **Cellular**
- Displays WiFi network name (SSID) — see if you're on "NMBS-WiFi" or "Starbucks"
- Color-coded quality indicator: green (excellent) → yellow (fair) → red (bad)
- Keeps a history of recent measurements so you can spot trends
- Runs silently in the menu bar — no dock icon, no window

## Requirements

- **macOS 13 (Ventura)** or later
- **Swift 5.9+** (included with Xcode 15+)
- No external dependencies — uses only Apple frameworks

## Quick Start

```bash
# Build
swift build

# Run
swift run NetworkBadge
```

The app will appear as a small icon + latency number in your menu bar. Click it to see full details.

## Build for Distribution

```bash
# Build the .app bundle
./scripts/build-app.sh

# Create a DMG for sharing
./scripts/create-dmg.sh
```

## Run Tests

```bash
swift test
```

## How It Works

| Component | Framework | Purpose |
|-----------|-----------|---------|
| Menu bar presence | SwiftUI `MenuBarExtra` | Shows icon + latency in the top bar |
| Network detection | `NWPathMonitor` (Network) | Detects WiFi, Ethernet, USB tethering |
| WiFi details | `CoreWLAN` | Reads SSID and signal info |
| Latency measurement | `URLSession` | HTTP ping to Apple's captive portal server |

### Why HTTP ping instead of ICMP?

1. **Works through captive portals** (train WiFi login pages)
2. **No root permissions** needed (ICMP requires elevated privileges)
3. **Tests real internet**, not just local network connectivity
4. Apple's server (`captive.apple.com`) is globally distributed and always available

## Project Structure

```
Sources/NetworkBadge/
├── NetworkBadgeApp.swift           # App entry point, MenuBarExtra
├── Models/
│   └── ConnectionInfo.swift        # Data types: ConnectionType, LatencyQuality
├── Monitors/
│   ├── NetworkMonitor.swift        # NWPathMonitor + WiFi SSID reading
│   └── LatencyMonitor.swift        # HTTP latency measurement loop
├── Views/
│   └── MenuBarView.swift           # Popover UI with network details
└── Helpers/
    └── NetworkInterfaceHelper.swift # Interface name → type detection

Tests/NetworkBadgeTests/
├── ConnectionInfoTests.swift       # Data model tests
├── LatencyMonitorTests.swift       # Latency logic tests
└── NetworkInterfaceHelperTests.swift # Interface detection tests

scripts/
├── build-app.sh                    # Compile + create .app bundle
└── create-dmg.sh                   # Package into .dmg for distribution
```

## Latency Quality Thresholds

| Quality | Latency | What it means |
|---------|---------|---------------|
| Excellent | < 30ms | Fiber-like, everything works great |
| Good | < 80ms | Normal browsing, video calls work |
| Fair | < 150ms | Usable but feels sluggish |
| Poor | < 300ms | Video calls will struggle |
| Bad | > 300ms | Barely functional |

These are tuned for typical European train WiFi and mobile hotspots.

## License

MIT
