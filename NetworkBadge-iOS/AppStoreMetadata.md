# App Store Metadata — Network Badge for iOS

Use this information when creating the app listing in App Store Connect.

## App Information

- **App Name:** Network Badge
- **Subtitle:** Travel Network Quality Monitor
- **Bundle ID:** com.networkbadge.ios
- **Primary Category:** Utilities
- **Secondary Category:** Travel
- **Content Rating:** 4+ (no objectionable content)
- **Price:** Free
- **Availability:** All territories

## Version Information

### Description

Network Badge monitors your internet quality on the go. Built for travelers who want to track WiFi and cellular performance on trains, in cafes, airports, and hotels.

Features:
- Live latency monitoring with color-coded quality indicators (Excellent, Good, Fair, Poor, Bad)
- GPS-tagged network quality recording — see exactly where your internet was good or bad
- Background tracking — keep recording while you travel with the app in the background
- Color-coded map trails showing network quality along your route
- Kalman-filtered GPS for smooth, accurate trail rendering
- Sparkline chart showing recent latency history at a glance
- Supports WiFi, Cellular, Ethernet, and VPN connections
- Quality predictions — get notified when rough connectivity is ahead based on historical data
- All data stays on your device — no cloud, no tracking, no analytics
- Export your data as CSV for analysis
- No ads, no subscriptions, no account required

Perfect for:
- Train commuters tracking WiFi quality along their route
- Remote workers finding cafes with reliable internet
- Travelers mapping cellular coverage in new areas
- Network engineers doing site surveys

### Keywords

network, latency, wifi, quality, monitor, travel, gps, ping, speed, cellular

### What's New (v1.0)

First release! Track network quality while traveling with GPS-mapped quality trails.

### Support URL

(your GitHub repository URL)

### Privacy Policy URL

(hosted privacy-policy.html URL)

## Screenshots Required

Capture these from the iOS Simulator with sample data loaded:

### iPhone 6.7" (iPhone 15 Pro Max) — 1290 x 2796px — minimum 3

1. **Dashboard tab** — showing live latency (e.g. "42 ms"), connection type "WiFi", sparkline chart, GPS tracking active with point count
2. **Map tab** — showing a color-coded quality trail on a route (green segments for good, red for bad)
3. **History tab** — showing a list of recorded quality measurements with quality badges
4. **Settings tab** (optional) — showing GPS tracking configuration

### iPhone 6.5" (iPhone 11 Pro Max) — 1242 x 2688px
Same screenshots, optional but recommended for wider device support.

### iPad 12.9" (iPad Pro) — 2048 x 2732px
Same screenshots, required only if you support iPad.

## App Review Notes

- The app requires location permission to function. GPS tracking must be enabled in the Settings tab to start recording quality measurements.
- Background location is used to continue recording network quality while the user travels (trains, walking, driving). The blue status bar indicator is shown when background tracking is active.
- The app makes HTTP requests to Apple's captive portal server (captive.apple.com) to measure network latency. This is not web browsing — it's a lightweight connectivity check.
- No account or login is required. All data is stored locally.

## Export Compliance

- **Uses encryption:** No (HTTPS via URLSession only — exempt)
- **ITSAppUsesNonExemptEncryption:** NO (set in Info.plist)

## Age Rating Questionnaire

All answers: **No**
- No violence, no adult content, no gambling, no horror, etc.
- Resulting rating: **4+**
