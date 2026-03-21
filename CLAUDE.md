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
- **CLLocationManager + GPS2IP** — GPS location tracking with iPhone fallback
- **LocationIntelligence** — Kalman filtering, outlier detection, and road snapping for clean trails
- **SQLite (WAL mode)** — append-only storage for GPS-tagged quality records
- **MapKit** — quality trail visualization with color-coded polylines
- **UserNotifications** — alerts on quality degradation, connection loss, and predictive warnings
- **ObservableObject + @Published pattern** — reactive data flow from monitors → UI

## Key Files

### App Entry
- `Sources/NetworkBadge/NetworkBadgeApp.swift` — App entry point, MenuBarExtra setup

### Monitors
- `Sources/NetworkBadge/Monitors/NetworkMonitor.swift` — Network type detection via NWPathMonitor
- `Sources/NetworkBadge/Monitors/LatencyMonitor.swift` — HTTP latency measurement
- `Sources/NetworkBadge/Monitors/LocationMonitor.swift` — GPS location tracking, records quality on significant moves
- `Sources/NetworkBadge/Monitors/LocationIntelligence.swift` — Kalman filtering, outlier detection, road snapping
- `Sources/NetworkBadge/Monitors/GPS2IPSource.swift` — TCP client for GPS2IP iOS app (NMEA over socket)
- `Sources/NetworkBadge/Monitors/NotificationManager.swift` — macOS notifications on quality changes
- `Sources/NetworkBadge/Monitors/UpdateChecker.swift` — GitHub release polling for app updates

### Models
- `Sources/NetworkBadge/Models/ConnectionInfo.swift` — Network connection data types
- `Sources/NetworkBadge/Models/QualityRecord.swift` — GPS-tagged quality measurement for storage
- `Sources/NetworkBadge/Models/RunDetector.swift` — Groups records into journeys by time gaps

### Storage
- `Sources/NetworkBadge/Storage/QualityDatabase.swift` — Append-only SQLite database for quality history
- `Sources/NetworkBadge/Storage/TileCache.swift` — Offline MapKit tile caching

### Views
- `Sources/NetworkBadge/Views/MenuBarView.swift` — Main popover UI
- `Sources/NetworkBadge/Views/SparklineView.swift` — Mini latency chart (green→red)
- `Sources/NetworkBadge/Views/QualityMapView.swift` — MapKit map with colored quality trails
- `Sources/NetworkBadge/Views/QualityTrailRenderer.swift` — Gradient polyline renderer for trail quality
- `Sources/NetworkBadge/Views/DataBrowserView.swift` — Table view for browsing records with CSV export
- `Sources/NetworkBadge/Views/SettingsView.swift` — Settings for notifications, location, latency targets
- `Sources/NetworkBadge/Views/MapWindowController.swift` — Map window lifecycle
- `Sources/NetworkBadge/Views/DataBrowserWindowController.swift` — Data browser window lifecycle
- `Sources/NetworkBadge/Views/SettingsWindowController.swift` — Settings window lifecycle

### Helpers
- `Sources/NetworkBadge/Helpers/NetworkInterfaceHelper.swift` — Interface type detection (WiFi, USB, VPN, etc.)
- `Sources/NetworkBadge/Helpers/CoordinateUtils.swift` — Haversine math for distance/bearing projection

### Tests
- `Tests/NetworkBadgeTests/` — Unit tests (10 test files covering models, monitors, storage, and views)

## Platform
- macOS 13+ (Ventura) required for MenuBarExtra
- Swift 5.9+
- No external dependencies — uses only Apple frameworks
