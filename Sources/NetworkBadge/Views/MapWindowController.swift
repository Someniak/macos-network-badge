// ---------------------------------------------------------
// MapWindowController.swift — Separate window for the quality map
//
// Opens a resizable NSWindow containing the QualityMapView.
// This is triggered from the menu bar popover via "Show Map".
//
// We use NSWindow directly (not WindowGroup) because:
//   1. MenuBarExtra apps can't use WindowGroup scenes
//   2. We need precise control over window appearance
//   3. The window should float above other windows
// ---------------------------------------------------------

import AppKit
import SwiftUI

/// Manages the map window lifecycle.
///
/// Usage:
///   let controller = MapWindowController(...)
///   controller.showWindow()   // opens or brings to front
///
/// The window is created once and reused. Closing it just hides it.
final class MapWindowController: ObservableObject {

    // MARK: - Published Properties

    /// Whether the map window is currently visible
    @Published var isWindowVisible: Bool = false

    // MARK: - Dependencies

    private let database: QualityDatabase
    private let tileCache: TileCache
    private weak var locationMonitor: LocationMonitor?

    // MARK: - Private Properties

    /// The actual NSWindow instance (created lazily)
    private var window: NSWindow?

    // MARK: - Initialization

    /// Creates a new map window controller.
    ///
    /// - Parameters:
    ///   - database: The quality database to read records from
    ///   - tileCache: The tile cache for offline map display
    ///   - locationMonitor: The location monitor for current position
    init(database: QualityDatabase, tileCache: TileCache, locationMonitor: LocationMonitor) {
        self.database = database
        self.tileCache = tileCache
        self.locationMonitor = locationMonitor
    }

    // MARK: - Window Management

    /// Shows the map window. Creates it on first call, brings to front on subsequent calls.
    func showWindow() {
        if let existingWindow = window {
            // Window already exists — bring it to front
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            isWindowVisible = true
            return
        }

        // Create the SwiftUI map view
        let mapView = QualityMapView(
            database: database,
            tileCache: tileCache,
            currentLatitude: locationMonitor?.latitude,
            currentLongitude: locationMonitor?.longitude,
            currentBearing: locationMonitor?.intelligence.currentBearing ?? 0
        )

        // Wrap in an NSHostingController for AppKit integration
        let hostingController = NSHostingController(rootView: mapView)

        // Create the window
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "Network Quality Map"
        newWindow.contentViewController = hostingController
        newWindow.setContentSize(NSSize(width: 800, height: 600))
        newWindow.minSize = NSSize(width: 500, height: 400)
        newWindow.isReleasedWhenClosed = false
        newWindow.center()

        // Set up close notification so we track visibility
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            self?.isWindowVisible = false
        }

        // Show the window
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
        self.isWindowVisible = true
    }

    /// Closes the map window if it's open.
    func closeWindow() {
        window?.close()
        isWindowVisible = false
    }
}
