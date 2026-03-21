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

    /// Controls the settings window
    @ObservedObject var settingsWindowController: SettingsWindowController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Connection Info ─────────────────────────
            connectionSection

            Divider()

            // ── Latency Info + Sparkline ─────────────────
            latencySection

            // ── Quality Stats (score, loss, jitter) ──────
            statsRow

            SparklineView(samples: latencyMonitor.samples)
                .frame(height: 60)

            Divider()

            // ── GPS status + actions ─────────────────────
            bottomRow
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

    // MARK: - Quality Stats Row

    /// Shows quality score, packet loss, and jitter on one compact line.
    private var statsRow: some View {
        HStack(spacing: 12) {
            // Quality score (0-100)
            if let score = latencyMonitor.qualityScore {
                HStack(spacing: 3) {
                    Text("\(score)")
                        .font(.system(.subheadline, design: .rounded).bold().monospacedDigit())
                        .foregroundColor(qualityScoreColor(score))
                    Text("/ 100")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Packet loss
            if !latencyMonitor.samples.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "xmark.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f%%", latencyMonitor.packetLossPercent))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(latencyMonitor.packetLossPercent > 10 ? .orange : .secondary)
                }
                .help("Packet loss")
            }

            // Jitter
            if let jitter = latencyMonitor.jitterMs {
                HStack(spacing: 2) {
                    Image(systemName: "waveform.path")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("±\(Int(jitter))ms")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(jitter > 50 ? .orange : .secondary)
                }
                .help("Jitter")
            }
        }
    }

    // MARK: - Bottom row (GPS status + actions)

    /// GPS status on the left; Show Map, Settings, Quit on the right — all on one line.
    private var bottomRow: some View {
        HStack(spacing: 6) {
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

            HoverIconButton(icon: "map", hoverColor: .accentColor, action: { mapWindowController.showWindow() })
                .help("Show Map")
            HoverIconButton(icon: "gear", hoverColor: .primary, action: { settingsWindowController.showWindow() })
                .help("Settings")
            HoverIconButton(icon: "power", hoverColor: .red, action: { NSApplication.shared.terminate(nil) })
                .help("Exit Network Badge")
        }
    }
}

// MARK: - Hover helpers

private struct HoverIconButton: View {
    let icon: String
    let hoverColor: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isHovered ? hoverColor : .secondary)
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(isHovered ? 0.12 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

private struct HoverTextButton: View {
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(isHovered ? .white : .accentColor)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHovered ? Color.accentColor : Color.accentColor.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}
