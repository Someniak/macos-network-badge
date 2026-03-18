// ---------------------------------------------------------
// MenuBarView.swift — The popover UI shown when you click
//                     the menu bar icon
//
// This view shows all network details in a clean popover:
//   - Connection type with icon (WiFi, Ethernet, USB, etc.)
//   - WiFi network name (SSID) and signal strength
//   - Current latency (big and prominent)
//   - Average latency and quality indicator
//   - Sparkline chart of recent measurements
//   - GPS tracking status and "Show Map" button
//   - Settings (Launch at Login, Alert on Poor Connection)
//   - Quit button
// ---------------------------------------------------------

import ServiceManagement
import SwiftUI

/// The main popover view shown when the user clicks the menu bar item.
struct MenuBarView: View {

    /// The network monitor — tells us connection type, SSID, signal, etc.
    @ObservedObject var networkMonitor: NetworkMonitor

    /// The latency monitor — tells us ping times, quality, etc.
    @ObservedObject var latencyMonitor: LatencyMonitor

    /// The notification manager — controls quality drop alerts
    @ObservedObject var notificationManager: NotificationManager

    /// The location monitor — tracks GPS for quality mapping
    @ObservedObject var locationMonitor: LocationMonitor

    /// Controls the separate map window
    @ObservedObject var mapWindowController: MapWindowController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Connection Info ─────────────────────────
            connectionSection

            Divider()

            // ── Latency Info + Sparkline ─────────────────
            latencySection

            SparklineView(samples: latencyMonitor.samples)
                .frame(height: 60)

            Divider()

            // ── Quality Map ─────────────────────────────
            mapSection

            Divider()

            // ── Settings ──────────────────────────────
            settingsSection

            Divider()

            // ── Footer ─────────────────────────────────
            footerSection
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: - Connection Info

    /// One-line row: icon + type + SSID + signal quality dot
    private var connectionSection: some View {
        HStack(spacing: 8) {
            Image(systemName: networkMonitor.connectionType.symbolName)
                .frame(width: 20)
            Text(networkMonitor.connectionType.rawValue)
                .font(.body.bold())
            if let ssid = networkMonitor.wifiSSID {
                Text(ssid)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            // Signal quality dot: WiFi uses signal color, otherwise connected/disconnected
            Circle()
                .fill(signalDotColor)
                .frame(width: 8, height: 8)
        }
    }

    /// Color for the status dot in the connection row
    private var signalDotColor: Color {
        if let rssi = networkMonitor.wifiRSSI {
            return WiFiSignalQuality.from(rssi: rssi).swiftUIColor
        }
        return networkMonitor.isConnected ? Color.green : Color.red
    }

    // MARK: - Latency Info

    /// Single row: big latency + quality badge + avg
    private var latencySection: some View {
        HStack(spacing: 8) {
            if let latency = latencyMonitor.currentLatencyMs {
                Text("\(Int(latency)) ms")
                    .font(.title2.monospacedDigit().bold())
                    .foregroundColor(latencyMonitor.quality.swiftUIColor)
            } else {
                Text("-- ms")
                    .font(.title2.bold())
                    .foregroundColor(.secondary)
            }

            Text(latencyMonitor.quality.rawValue)
                .font(.caption.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(latencyMonitor.quality.swiftUIColor.opacity(0.2))
                .cornerRadius(4)
                .foregroundColor(latencyMonitor.quality.swiftUIColor)

            Spacer()

            if let avg = latencyMonitor.averageLatencyMs {
                Text("avg \(Int(avg)) ms")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Quality Map

    /// Shows GPS tracking status and a button to open the map window.
    /// The map shows all recorded network quality measurements as
    /// colored dots overlaid on a real map.
    private var mapSection: some View {
        HStack(spacing: 8) {
            // GPS status indicator
            if locationMonitor.isTracking {
                Image(systemName: "location.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("Tracking")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if locationMonitor.sessionRecordCount > 0 {
                    Text("(\(locationMonitor.sessionRecordCount) pts)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !locationMonitor.isAuthorized {
                Image(systemName: "location.slash")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("Location off")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "location")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Waiting for GPS")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Open map window button
            Button(action: {
                mapWindowController.showWindow()
            }) {
                Label("Show Map", systemImage: "map")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Settings

    /// Checkboxes side by side
    private var settingsSection: some View {
        HStack {
            Toggle("Launch at Login", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        print("Failed to update login item: \(error)")
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .font(.subheadline)

            Spacer()

            Toggle("Alerts", isOn: $notificationManager.notificationsEnabled)
                .toggleStyle(.checkbox)
                .font(.subheadline)
        }
    }

    // MARK: - Footer

    /// Quit button and app info
    private var footerSection: some View {
        HStack {
            Text("Measuring every \(Int(latencyMonitor.measurementInterval))s")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Image(systemName: "power")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Exit Network Badge")
        }
    }
}
