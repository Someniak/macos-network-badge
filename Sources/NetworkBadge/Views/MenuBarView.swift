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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── Header ──────────────────────────────────
            headerSection

            Divider()

            // ── Connection Info ─────────────────────────
            connectionSection

            Divider()

            // ── Latency Info ────────────────────────────
            latencySection

            Divider()

            // ── Sparkline Chart ─────────────────────────
            sparklineSection

            Divider()

            // ── Settings ──────────────────────────────
            settingsSection

            Divider()

            // ── Footer ─────────────────────────────────
            footerSection
        }
        .padding(16)
        .frame(width: 280)
    }

    // MARK: - Header

    /// App title at the top of the popover
    private var headerSection: some View {
        HStack {
            Image(systemName: "network")
                .font(.title2)
            Text("Network Badge")
                .font(.headline)
            Spacer()
        }
    }

    // MARK: - Connection Info

    /// Shows what type of network you're on, SSID, and signal strength
    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Connection type with icon
            HStack(spacing: 8) {
                Image(systemName: networkMonitor.connectionType.symbolName)
                    .frame(width: 20)
                Text(networkMonitor.connectionType.rawValue)
                    .font(.body.bold())
                Spacer()
                // Green/red dot for connected/disconnected
                Circle()
                    .fill(networkMonitor.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }

            // WiFi network name (only shown when on WiFi)
            if let ssid = networkMonitor.wifiSSID {
                HStack(spacing: 8) {
                    Image(systemName: "wifi")
                        .frame(width: 20)
                        .foregroundColor(.secondary)
                    Text(ssid)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // WiFi signal strength (only shown when on WiFi with RSSI data)
            if let rssi = networkMonitor.wifiRSSI {
                let signalQuality = WiFiSignalQuality.from(rssi: rssi)
                HStack(spacing: 8) {
                    Image(systemName: signalQuality.symbolName)
                        .frame(width: 20)
                        .foregroundColor(signalQuality.swiftUIColor)
                    Text("\(rssi) dBm")
                        .font(.subheadline)
                    Spacer()
                    Text(signalQuality.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Interface name (e.g. "en0")
            if !networkMonitor.interfaceName.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .frame(width: 20)
                        .foregroundColor(.secondary)
                    Text(NetworkInterfaceHelper.displayName(
                        forInterface: networkMonitor.interfaceName
                    ))
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Latency Info

    /// Shows the current and average latency with quality indicator
    private var latencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Current latency — big and prominent
            HStack {
                Text("Latency")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if let latency = latencyMonitor.currentLatencyMs {
                    Text("\(Int(latency)) ms")
                        .font(.title2.monospacedDigit().bold())
                        .foregroundColor(latencyMonitor.quality.swiftUIColor)
                } else {
                    Text("--")
                        .font(.title2.bold())
                        .foregroundColor(.secondary)
                }
            }

            // Quality badge
            HStack {
                Text("Quality")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(latencyMonitor.quality.rawValue)
                    .font(.subheadline.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        latencyMonitor.quality.swiftUIColor.opacity(0.2)
                    )
                    .cornerRadius(4)
                    .foregroundColor(latencyMonitor.quality.swiftUIColor)
            }

            // Average latency
            HStack {
                Text("Average")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if let avg = latencyMonitor.averageLatencyMs {
                    Text("\(Int(avg)) ms")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                } else {
                    Text("--")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Sparkline Chart

    /// Shows a mini line chart of recent latency measurements
    private var sparklineSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("History")
                .font(.subheadline)
                .foregroundColor(.secondary)

            SparklineView(samples: latencyMonitor.samples)
                .frame(height: 60)
        }
    }

    // MARK: - Settings

    /// Launch at Login toggle and notification toggle
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
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

            Toggle("Alert on Poor Connection", isOn: $notificationManager.notificationsEnabled)
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
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
    }
}
