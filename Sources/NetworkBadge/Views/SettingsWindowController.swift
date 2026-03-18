// ---------------------------------------------------------
// SettingsWindowController.swift — Separate settings window
//
// Opens a small NSWindow containing SettingsView.
// Triggered from the menu bar popover via the gear button.
// ---------------------------------------------------------

import AppKit
import SwiftUI

final class SettingsWindowController: ObservableObject {

    private var window: NSWindow?

    private weak var notificationManager: NotificationManager?
    private weak var locationMonitor: LocationMonitor?
    private weak var latencyMonitor: LatencyMonitor?

    init(
        notificationManager: NotificationManager,
        locationMonitor: LocationMonitor,
        latencyMonitor: LatencyMonitor
    ) {
        self.notificationManager = notificationManager
        self.locationMonitor = locationMonitor
        self.latencyMonitor = latencyMonitor
    }

    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let nm = notificationManager,
              let lm = locationMonitor,
              let lat = latencyMonitor else { return }

        let settingsView = SettingsView(
            notificationManager: nm,
            locationMonitor: lm,
            latencyMonitor: lat
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
        newWindow.setContentSize(hostingController.view.fittingSize)
        newWindow.isReleasedWhenClosed = false
        newWindow.center()

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }
}
