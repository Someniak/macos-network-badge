// ---------------------------------------------------------
// MenuBarView.swift — The popover UI shown when you click
//                     the menu bar icon
//
// This view shows all network details in a clean popover:
//   - Connection type with icon (WiFi, Ethernet, USB, etc.)
//   - WiFi network name (SSID) if applicable
//   - Current latency (big and prominent)
//   - Average latency and quality indicator
//   - Recent measurement history
//   - Quit button
// ---------------------------------------------------------

import SwiftUI

/// The main popover view shown when the user clicks the menu bar item.
struct MenuBarView: View {

    /// The network monitor — tells us connection type, SSID, etc.
    @ObservedObject var networkMonitor: NetworkMonitor

    /// The latency monitor — tells us ping times, quality, etc.
    @ObservedObject var latencyMonitor: LatencyMonitor

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

            // ── Recent History ──────────────────────────
            historySection

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

    /// Shows what type of network you're on and the SSID if WiFi
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
                        .foregroundColor(colorForQuality(latencyMonitor.quality))
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
                        colorForQuality(latencyMonitor.quality).opacity(0.2)
                    )
                    .cornerRadius(4)
                    .foregroundColor(colorForQuality(latencyMonitor.quality))
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

    // MARK: - History

    /// Shows the last few latency measurements
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if latencyMonitor.samples.isEmpty {
                Text("No measurements yet…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                // Show last 8 measurements in a compact format
                let recentSamples = Array(latencyMonitor.samples.prefix(8))
                ForEach(recentSamples) { sample in
                    HStack {
                        // Timestamp
                        Text(formatTime(sample.timestamp))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .leading)

                        // Latency bar (visual indicator)
                        if sample.wasSuccessful {
                            let quality = LatencyQuality.from(latencyMs: sample.latencyMs)
                            Rectangle()
                                .fill(colorForQuality(quality))
                                .frame(
                                    width: min(CGFloat(sample.latencyMs) / 2.0, 120),
                                    height: 4
                                )
                                .cornerRadius(2)
                        } else {
                            Text("✕")
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Spacer()

                        // Latency value
                        Text(sample.displayText)
                            .font(.caption.monospacedDigit())
                            .frame(width: 55, alignment: .trailing)
                    }
                }
            }
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
                // NSApplication.shared.terminate sends the app a quit message
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
    }

    // MARK: - Helpers

    /// Maps a LatencyQuality to a SwiftUI Color
    private func colorForQuality(_ quality: LatencyQuality) -> Color {
        switch quality {
        case .excellent: return .green
        case .good:      return .green
        case .fair:      return .yellow
        case .poor:      return .orange
        case .bad:       return .red
        case .unknown:   return .gray
        }
    }

    /// Formats a timestamp as "HH:mm:ss" (e.g. "14:32:05")
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
