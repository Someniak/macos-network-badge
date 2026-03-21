// ---------------------------------------------------------
// SettingsWindowController.swift — Separate settings window
//
// Opens a small NSWindow containing SettingsView.
// Triggered from the menu bar popover via the gear button.
// ---------------------------------------------------------

#if os(macOS)
import AppKit
import SwiftUI

final class SettingsWindowController: ObservableObject {

    private var window: NSWindow?

    private weak var notificationManager: NotificationManager?
    private weak var locationMonitor: LocationMonitor?
    private weak var latencyMonitor: LatencyMonitor?
    private weak var updateChecker: UpdateChecker?

    init(
        notificationManager: NotificationManager,
        locationMonitor: LocationMonitor,
        latencyMonitor: LatencyMonitor,
        updateChecker: UpdateChecker
    ) {
        self.notificationManager = notificationManager
        self.locationMonitor = locationMonitor
        self.latencyMonitor = latencyMonitor
        self.updateChecker = updateChecker
    }

    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let nm = notificationManager,
              let lm = locationMonitor,
              let lat = latencyMonitor,
              let uc = updateChecker else { return }

        let settingsView = SettingsView(
            notificationManager: nm,
            locationMonitor: lm,
            latencyMonitor: lat,
            updateChecker: uc
        )

        let hostingController = NSHostingController(rootView: settingsView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "Settings"
        newWindow.contentViewController = hostingController
        let fitting = hostingController.view.fittingSize
        let maxHeight: CGFloat = 600
        newWindow.setContentSize(NSSize(width: fitting.width, height: min(fitting.height, maxHeight)))
        newWindow.contentMinSize = NSSize(width: fitting.width, height: 300)
        newWindow.contentMaxSize = NSSize(width: fitting.width, height: maxHeight)
        newWindow.isReleasedWhenClosed = false
        newWindow.center()

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }
}
#endif
