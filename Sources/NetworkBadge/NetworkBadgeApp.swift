// ---------------------------------------------------------
// NetworkBadgeApp.swift — Main entry point for the app
//
// This is where everything starts. The @main attribute tells
// Swift this is the app's entry point. We create a MenuBarExtra
// (the icon/text in your menu bar) and wire up the monitors.
//
// The app:
//   1. Shows a small colored text in the menu bar: "● 42ms"
//   2. When clicked, shows a popover with full network details
//   3. Sends notifications when quality drops to poor/bad
//   4. Runs in the background (no dock icon, no window)
//   5. Tracks network quality with GPS for map visualization
//   6. Stores all measurements in ~/.networkbadge/ for future analysis
// ---------------------------------------------------------

#if os(macOS)
import SwiftUI

/// The main app. Uses SwiftUI's App protocol with MenuBarExtra
/// to create a menu-bar-only application (no dock icon, no window).
@main
struct NetworkBadgeApp: App {

    // MARK: - Monitors

    /// Watches for network type changes (WiFi, Ethernet, USB, etc.)
    @StateObject private var networkMonitor: NetworkMonitor

    /// Measures internet latency every few seconds
    @StateObject private var latencyMonitor: LatencyMonitor

    /// Manages quality-drop notifications
    @StateObject private var notificationManager: NotificationManager

    // MARK: - GPS Quality Tracking

    /// SQLite database for persistent quality records (~/.networkbadge/quality.db)
    /// Data is NEVER deleted — designed for future predictive analysis.
    private let qualityDatabase: QualityDatabase

    /// Tile cache for offline map display (~/.networkbadge/tiles/)
    private let tileCache: TileCache

    /// GPS location tracker — records measurements when you move
    @StateObject private var locationMonitor: LocationMonitor

    /// Controls the separate map window
    @StateObject private var mapWindowController: MapWindowController

    /// Controls the settings window
    @StateObject private var settingsWindowController: SettingsWindowController

    /// Checks GitHub Releases for app updates
    @StateObject private var updateChecker: UpdateChecker

    // MARK: - Initialization

    /// Sets up the database, tile cache, location monitor, and map window.
    /// The database and tile cache are created first (they don't need @StateObject),
    /// then passed to the location monitor and map window controller.
    init() {
        let db = QualityDatabase()
        let cache = TileCache()
        let locMonitor = LocationMonitor(database: db)
        let notifManager = NotificationManager()
        let latMonitor = LatencyMonitor()
        let netMonitor = NetworkMonitor()
        let mapController = MapWindowController(
            database: db,
            tileCache: cache,
            locationMonitor: locMonitor,
            latencyMonitor: latMonitor,
            networkMonitor: netMonitor
        )
        let updateChk = UpdateChecker()
        let settingsController = SettingsWindowController(
            notificationManager: notifManager,
            locationMonitor: locMonitor,
            latencyMonitor: latMonitor,
            updateChecker: updateChk
        )

        // Use the shared instances
        self.qualityDatabase = db
        self.tileCache = cache
        _networkMonitor = StateObject(wrappedValue: netMonitor)
        _latencyMonitor = StateObject(wrappedValue: latMonitor)
        _notificationManager = StateObject(wrappedValue: notifManager)
        _locationMonitor = StateObject(wrappedValue: locMonitor)
        _updateChecker = StateObject(wrappedValue: updateChk)
        _mapWindowController = StateObject(wrappedValue: mapController)
        _settingsWindowController = StateObject(wrappedValue: settingsController)
    }

    // MARK: - App Body

    var body: some Scene {
        // MenuBarExtra is a SwiftUI scene that creates a menu bar item.
        // It has two parts:
        //   1. "label" — what's shown in the menu bar (always visible)
        //   2. "content" — the popover shown when you click it

        MenuBarExtra {
            // ── Popover Content ─────────────────────────
            // This is the detailed view shown when clicked
            MenuBarView(
                networkMonitor: networkMonitor,
                latencyMonitor: latencyMonitor,
                notificationManager: notificationManager,
                locationMonitor: locationMonitor,
                mapWindowController: mapWindowController,
                settingsWindowController: settingsWindowController,
                updateChecker: updateChecker
            )
        } label: {
            // ── Menu Bar Label ──────────────────────────
            // This is the tiny text always visible in the menu bar.
            // Shows something like "● 42ms" with a colored dot.
            menuBarLabel
        }
        // .window style shows the content as a popover (not a menu)
        .menuBarExtraStyle(.window)
    }

    // MARK: - Menu Bar Label

    /// The text shown in the menu bar. Kept very short to not
    /// take up too much space. Shows:
    ///   - "● 42ms" when connected (colored by quality)
    ///   - "○ --"   when disconnected
    private var menuBarLabel: some View {
        HStack(spacing: 4) {
            // Network type icon
            Image(systemName: networkMonitor.connectionType.symbolName)
                .font(.caption2)

            // Latency text
            if let latency = latencyMonitor.currentLatencyMs {
                Text("\(Int(latency))ms")
                    .monospacedDigit()
                    .font(.caption)
            } else {
                Text("--")
                    .font(.caption)
            }
        }
        // Color the entire menu bar label by quality
        .foregroundColor(latencyMonitor.quality.swiftUIColor)
        // Start all monitors when the app appears
        .onAppear {
            networkMonitor.start()
            latencyMonitor.start()
            notificationManager.requestPermission()
            // Start GPS tracking (will request location permission on first launch)
            locationMonitor.start(
                networkMonitor: networkMonitor,
                latencyMonitor: latencyMonitor
            )
        }
        // Watch for quality changes and send notifications on degradation
        .onChange(of: latencyMonitor.quality) { newQuality in
            notificationManager.notifyQualityDrop(
                to: newQuality,
                latencyMs: latencyMonitor.currentLatencyMs ?? 0
            )
        }
        // Watch for connection type changes and alert on disconnection
        .onChange(of: networkMonitor.connectionType) { newType in
            notificationManager.notifyConnectionChange(to: newType)
        }
        // Watch for spatial lookahead predictions and alert on rough connectivity ahead
        .onChange(of: locationMonitor.intelligence.lookaheadPrediction) { newPrediction in
            notificationManager.notifyPredictionChange(to: newPrediction)
        }
    }
}
#endif
