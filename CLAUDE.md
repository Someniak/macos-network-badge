# Network Badge - macOS & iOS Network Quality Monitor

## Project Overview
A native network quality monitor (Swift/SwiftUI) that shows live network latency
and connection type. Built for travellers who want to monitor their internet
quality on trains, cafés, etc.

- **macOS**: Menu bar app with popover UI, separate map/settings windows
- **iOS**: Tab-based app focused on GPS tracking on the go

Both platforms share the same monitors, models, storage, and core views.
Platform-specific code uses `#if os(macOS)` / `#if os(iOS)` guards.

## Build Commands
```bash
# Build macOS (debug)
swift build

# Build macOS (release)
swift build -c release

# Run macOS locally (after building)
swift run NetworkBadge

# Build macOS .app bundle
./scripts/build-app.sh

# Create DMG for distribution
./scripts/create-dmg.sh

# Build iOS (requires Xcode)
./scripts/build-ios.sh              # simulator
./scripts/build-ios.sh device       # device
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
- **SwiftUI TabView** — tab-based navigation (iOS 16+)
- **NWPathMonitor** — detects network interface type (WiFi, Ethernet, Cellular, etc.)
- **CoreWLAN** — reads WiFi SSID and signal info (macOS only)
- **URLSession** — measures HTTP latency to detect real internet quality
- **CLLocationManager + GPS2IP** — GPS location tracking with iPhone fallback (macOS)
- **CLLocationManager (background)** — native GPS tracking on the go (iOS)
- **LocationIntelligence** — Kalman filtering, outlier detection, and road snapping for clean trails
- **SQLite (WAL mode)** — append-only storage for GPS-tagged quality records
- **MapKit** — quality trail visualization with color-coded polylines
- **UserNotifications** — alerts on quality degradation, connection loss, and predictive warnings
- **ObservableObject + @Published pattern** — reactive data flow from monitors → UI

## Key Files

### App Entry Points
- `Sources/NetworkBadge/NetworkBadgeApp.swift` — macOS entry point, MenuBarExtra setup (`#if os(macOS)`)
- `Sources/NetworkBadge/NetworkBadgeIOSApp.swift` — iOS entry point, TabView setup (`#if os(iOS)`)

### Monitors (cross-platform)
- `Sources/NetworkBadge/Monitors/NetworkMonitor.swift` — Network type detection via NWPathMonitor
- `Sources/NetworkBadge/Monitors/LatencyMonitor.swift` — HTTP latency measurement
- `Sources/NetworkBadge/Monitors/LocationMonitor.swift` — GPS location tracking, records quality on significant moves
- `Sources/NetworkBadge/Monitors/LocationIntelligence.swift` — Kalman filtering, outlier detection, road snapping
- `Sources/NetworkBadge/Monitors/GPS2IPSource.swift` — TCP client for GPS2IP iOS app (NMEA over socket)
- `Sources/NetworkBadge/Monitors/NotificationManager.swift` — Notifications on quality changes
- `Sources/NetworkBadge/Monitors/UpdateChecker.swift` — GitHub release polling for app updates

### Models (cross-platform)
- `Sources/NetworkBadge/Models/ConnectionInfo.swift` — Network connection data types
- `Sources/NetworkBadge/Models/QualityRecord.swift` — GPS-tagged quality measurement for storage
- `Sources/NetworkBadge/Models/RunDetector.swift` — Groups records into journeys by time gaps

### Storage (cross-platform)
- `Sources/NetworkBadge/Storage/QualityDatabase.swift` — Append-only SQLite database for quality history
- `Sources/NetworkBadge/Storage/TileCache.swift` — Offline MapKit tile caching

### Views — macOS only (`#if os(macOS)`)
- `Sources/NetworkBadge/Views/MenuBarView.swift` — Main popover UI
- `Sources/NetworkBadge/Views/DataBrowserView.swift` — Table view for browsing records with CSV export
- `Sources/NetworkBadge/Views/SettingsView.swift` — Settings for notifications, location, latency targets
- `Sources/NetworkBadge/Views/MapWindowController.swift` — Map window lifecycle
- `Sources/NetworkBadge/Views/DataBrowserWindowController.swift` — Data browser window lifecycle
- `Sources/NetworkBadge/Views/SettingsWindowController.swift` — Settings window lifecycle

### Views — iOS only (`#if os(iOS)`)
- `Sources/NetworkBadge/Views/DashboardView.swift` — Live latency, connection type, sparkline, GPS status
- `Sources/NetworkBadge/Views/DataListView.swift` — SwiftUI List for browsing records with CSV share
- `Sources/NetworkBadge/Views/IOSSettingsView.swift` — Settings (notifications, polling, GPS tracking)

### Views — Cross-platform
- `Sources/NetworkBadge/Views/SparklineView.swift` — Mini latency chart (green→red)
- `Sources/NetworkBadge/Views/QualityMapView.swift` — MapKit map with colored quality trails
- `Sources/NetworkBadge/Views/QualityTrailRenderer.swift` — Gradient polyline renderer (NSViewRepresentable/UIViewRepresentable)

### Helpers (cross-platform)
- `Sources/NetworkBadge/Helpers/NetworkInterfaceHelper.swift` — Interface type detection (WiFi, USB, VPN, etc.)
- `Sources/NetworkBadge/Helpers/CoordinateUtils.swift` — Haversine math for distance/bearing projection

### iOS Configuration
- `NetworkBadge-iOS/Info.plist` — Background location modes, permission strings, ATS config
- `NetworkBadge-iOS/NetworkBadge.entitlements` — Location entitlements

### Tests
- `Tests/NetworkBadgeTests/` — Unit tests (10 test files covering models, monitors, storage, and views)

## Platform
- macOS 13+ (Ventura) required for MenuBarExtra
- iOS 16+ required for NavigationStack
- Swift 5.9+
- No external dependencies — uses only Apple frameworks

## Cross-Platform Notes
- All `#if os()` guards are in shared files; platform-specific files are wrapped entirely
- CoreWLAN (WiFi SSID/RSSI) is macOS-only; uses `#if canImport(CoreWLAN)`
- GPS2IP is macOS-only (iOS has native GPS — no need for iPhone fallback)
- iOS uses background location updates (`allowsBackgroundLocationUpdates = true`)
- Database path: `~/.networkbadge/` on macOS, `ApplicationSupport/NetworkBadge/` on iOS
- QualityTrailRenderer uses `NSViewRepresentable` on macOS, `UIViewRepresentable` on iOS
