// ---------------------------------------------------------
// NetworkBadgeIOSApp.swift — iOS app entry point
//
// Tab-based iOS app for tracking network quality on the go.
// GPS tracking is the primary feature — records network
// quality measurements as you move (trains, cars, walking).
// ---------------------------------------------------------

#if os(iOS)
import SwiftUI

@main
struct NetworkBadgeIOSApp: App {

    // MARK: - Monitors

    /// Watches for network type changes (WiFi, Cellular, etc.)
    @StateObject private var networkMonitor: NetworkMonitor

    /// Measures internet latency every few seconds
    @StateObject private var latencyMonitor: LatencyMonitor

    /// Manages quality-drop notifications
    @StateObject private var notificationManager: NotificationManager

    // MARK: - GPS Quality Tracking

    /// SQLite database for persistent quality records
    private let qualityDatabase: QualityDatabase

    /// Tile cache for offline map display
    private let tileCache: TileCache

    /// GPS location tracker — records measurements when you move
    @StateObject private var locationMonitor: LocationMonitor

    /// Checks GitHub Releases for app updates
    @StateObject private var updateChecker: UpdateChecker

    // MARK: - Initialization

    init() {
        let db = QualityDatabase()
        let cache = TileCache()
        let locMonitor = LocationMonitor(database: db)
        let notifManager = NotificationManager()
        let latMonitor = LatencyMonitor()
        let netMonitor = NetworkMonitor()
        let updateChk = UpdateChecker()

        self.qualityDatabase = db
        self.tileCache = cache
        _networkMonitor = StateObject(wrappedValue: netMonitor)
        _latencyMonitor = StateObject(wrappedValue: latMonitor)
        _notificationManager = StateObject(wrappedValue: notifManager)
        _locationMonitor = StateObject(wrappedValue: locMonitor)
        _updateChecker = StateObject(wrappedValue: updateChk)
    }

    // MARK: - App Body

    var body: some Scene {
        WindowGroup {
            TabView {
                DashboardView(
                    networkMonitor: networkMonitor,
                    latencyMonitor: latencyMonitor,
                    locationMonitor: locationMonitor,
                    notificationManager: notificationManager
                )
                .tabItem {
                    Label("Dashboard", systemImage: "gauge.medium")
                }

                QualityMapView(
                    database: qualityDatabase,
                    tileCache: tileCache,
                    locationMonitor: locationMonitor,
                    latencyMonitor: latencyMonitor,
                    networkMonitor: networkMonitor
                )
                .tabItem {
                    Label("Map", systemImage: "map")
                }

                DataListView(database: qualityDatabase)
                    .tabItem {
                        Label("History", systemImage: "list.bullet")
                    }

                IOSSettingsView(
                    notificationManager: notificationManager,
                    locationMonitor: locationMonitor,
                    latencyMonitor: latencyMonitor,
                    updateChecker: updateChecker
                )
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
            }
            .onAppear {
                networkMonitor.start()
                latencyMonitor.start()
                notificationManager.requestPermission()
                locationMonitor.start(
                    networkMonitor: networkMonitor,
                    latencyMonitor: latencyMonitor
                )
            }
            .onChange(of: latencyMonitor.quality) { newQuality in
                notificationManager.notifyQualityDrop(
                    to: newQuality,
                    latencyMs: latencyMonitor.currentLatencyMs ?? 0
                )
            }
            .onChange(of: networkMonitor.connectionType) { newType in
                notificationManager.notifyConnectionChange(to: newType)
            }
            .onChange(of: locationMonitor.intelligence.lookaheadPrediction) { newPrediction in
                notificationManager.notifyPredictionChange(to: newPrediction)
            }
        }
    }
}
#endif
