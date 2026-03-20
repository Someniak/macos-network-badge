# Changelog

All notable changes to Network Badge are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

---

## [1.1.0] — 2026-03-20

### Added

- **GPS-based network quality tracking** — records latency measurements with GPS coordinates as you move, building a persistent quality database (`~/.networkbadge/quality.db`)
- **Interactive quality map** — separate map window with color-coded pins showing network quality at each recorded location, with offline tile caching
- **Smart location intelligence** — Kalman-smoothed GPS, outlier detection, speed estimation, bearing calculation, and stationary backoff polling to reduce battery drain
- **Quality trail renderer** — Uber-style colored trail on the map showing network quality along your route
- **GPS2IP support** — use your iPhone's GPS over Wi-Fi or USB via the GPS2IP app for higher-accuracy location on Macs without GPS hardware
- **IP geolocation fallback** — approximate location from IP address when GPS is unavailable
- **Coordinate utilities** — shared helpers for distance, bearing, and interpolation calculations
- **Run detector** — identifies movement sessions for grouping quality records
- **Data browser** — browse and inspect stored quality records
- **Auto-update checker** — periodically checks GitHub Releases for newer versions and notifies when an update is available (disabled in debug builds, skips prereleases)
- **Version display in Settings** — always shows the current app version in the General section
- **Sparkline chart** — visual history of recent latency measurements in the popover
- **Menu bar color coding** — menu bar label color reflects current connection quality
- **WiFi signal strength** — displays RSSI-based signal quality indicator
- **Categorized network alerts** — notifications are now typed: connection loss, latency degradation, and predictive "rough connection ahead"
- **Disconnection alerts** — get notified when WiFi, Ethernet, tethering, or cellular drops entirely
- **Predictive alerts** — "Rough Connection Ahead" notification fires when spatial lookahead predicts poor/bad connectivity in ~2 minutes (requires GPS tracking and sufficient historical data)
- **Per-type notification toggles** — independently enable/disable each alert type (latency, disconnection, prediction) in Settings, with a master toggle to silence all
- **Launch at Login** — toggle in Settings via `SMAppService`
- **Apache 2.0 license**
- **CI pipeline** — GitHub Actions for continuous integration (build + test on every push)
- **Automated release pipeline** — branch-based and manual-dispatch releases with DMG creation, SHA256 checksums, and merge-back PRs

### Changed

- **Settings window** — now a separate `NSWindow` (instead of inline in popover) with grouped form layout covering General, Polling, GPS Tracking, Location Intelligence, and GPS2IP sections
- **Menu bar popover** — streamlined single-row layout with connection info, latency + quality badge, sparkline, GPS status, and action buttons (map, settings, quit)
- **Polling target** — configurable with presets (Apple, Cloudflare, Google) and custom URL support
- **Notification body for timeouts** — shows "Connection timed out (bad)" instead of "Latency is now 0ms (bad)"
- **Build script** — now always ad-hoc code signs the app (required for macOS notification registration)

### Fixed

- Thread safety issues in `LocationMonitor` and `LocationIntelligence`
- Resource leaks in network monitoring
- Coordinate zero-check logic (OR to AND)
- Stale live position marker on map by observing `LocationMonitor`
- Backpropagation timestamp and trail filter logic
- Bearing update race condition (simplified to synchronous set)
- Notification delivery crash in test runner and CLI environments

---

## [1.0.0] — 2025-12-01

### Added

- Initial release
- macOS menu bar presence via `MenuBarExtra` (macOS 13+)
- Real-time latency measurement via `URLSession`
- Network type detection (WiFi, Ethernet, USB tethering, VPN) via `NWPathMonitor` and `CoreWLAN`
- WiFi SSID display
- Popover UI with connection details
- Quit button
