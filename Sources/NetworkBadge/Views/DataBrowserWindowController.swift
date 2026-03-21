// ---------------------------------------------------------
// DataBrowserWindowController.swift — Window for the data browser
//
// Opens a resizable NSWindow containing the DataBrowserView.
// Follows the same pattern as MapWindowController.
// ---------------------------------------------------------

#if os(macOS)
import AppKit
import SwiftUI

/// Manages the data browser window lifecycle.
///
/// Usage:
///   let controller = DataBrowserWindowController(database: db)
///   controller.showWindow()   // opens or brings to front
///
/// The window is created once and reused. Closing it just hides it.
final class DataBrowserWindowController: ObservableObject {

    // MARK: - Published Properties

    @Published var isWindowVisible: Bool = false

    // MARK: - Dependencies

    private let database: QualityDatabase

    // MARK: - Private Properties

    private var window: NSWindow?
    private var closeObserver: Any?

    // MARK: - Initialization

    init(database: QualityDatabase) {
        self.database = database
    }

    deinit {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Window Management

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            isWindowVisible = true
            return
        }

        let browserView = DataBrowserView(database: database)
        let hostingController = NSHostingController(rootView: browserView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "Data Browser"
        newWindow.contentViewController = hostingController
        newWindow.setContentSize(NSSize(width: 900, height: 500))
        newWindow.minSize = NSSize(width: 600, height: 300)
        newWindow.isReleasedWhenClosed = false
        newWindow.center()

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            self?.isWindowVisible = false
        }

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
        self.isWindowVisible = true
    }

    func closeWindow() {
        window?.close()
        isWindowVisible = false
    }
}
#endif
