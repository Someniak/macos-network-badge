// ---------------------------------------------------------
// DashboardView.swift — iOS dashboard showing live network status
//
// Shows connection type, latency, sparkline, and GPS tracking
// status. The primary view for at-a-glance network quality.
// ---------------------------------------------------------

#if os(iOS)
import SwiftUI

struct DashboardView: View {

    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var latencyMonitor: LatencyMonitor
    @ObservedObject var locationMonitor: LocationMonitor
    @ObservedObject var notificationManager: NotificationManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Connection card
                    connectionCard

                    // Latency card
                    latencyCard

                    // Sparkline
                    SparklineView(samples: latencyMonitor.samples)
                        .frame(height: 100)
                        .padding(.horizontal)

                    // GPS tracking card
                    trackingCard

                    // Quick stats
                    statsCard
                }
                .padding(.vertical)
            }
            .navigationTitle("Network Badge")
        }
    }

    // MARK: - Connection Card

    private var connectionCard: some View {
        HStack(spacing: 12) {
            Image(systemName: networkMonitor.connectionType.symbolName)
                .font(.title2)
                .foregroundColor(networkMonitor.isConnected ? .green : .red)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(networkMonitor.connectionType.rawValue)
                    .font(.headline)
                if let ssid = networkMonitor.wifiSSID {
                    Text(ssid)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Signal quality dot
            Circle()
                .fill(signalDotColor)
                .frame(width: 12, height: 12)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var signalDotColor: Color {
        if let rssi = networkMonitor.wifiRSSI {
            return WiFiSignalQuality.from(rssi: rssi).swiftUIColor
        }
        return networkMonitor.isConnected ? Color.green : Color.red
    }

    // MARK: - Latency Card

    private var latencyCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Latency")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let latency = latencyMonitor.currentLatencyMs {
                    Text("\(Int(latency)) ms")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(latencyMonitor.quality.swiftUIColor)
                } else {
                    Text("-- ms")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                // Quality badge
                Text(latencyMonitor.quality.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(latencyMonitor.quality.swiftUIColor.opacity(0.2))
                    .cornerRadius(6)
                    .foregroundColor(latencyMonitor.quality.swiftUIColor)

                // Average
                if let avg = latencyMonitor.averageLatencyMs {
                    Text("avg \(Int(avg)) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                // Jitter
                if let jitter = latencyMonitor.jitter {
                    Text("jitter \(Int(jitter)) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Tracking Card

    private var trackingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: locationMonitor.isTracking ? "location.fill" : "location.slash")
                    .foregroundColor(locationMonitor.isTracking ? .green : .orange)
                Text("GPS Tracking")
                    .font(.headline)
                Spacer()

                Toggle("", isOn: $locationMonitor.isTrackingEnabled)
                    .labelsHidden()
            }

            if locationMonitor.isTrackingEnabled {
                HStack(spacing: 16) {
                    if locationMonitor.isTracking {
                        Label("\(locationMonitor.sessionRecordCount) pts", systemImage: "mappin.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let lat = locationMonitor.latitude, let lon = locationMonitor.longitude {
                        Text(String(format: "%.4f, %.4f", lat, lon))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    if locationMonitor.intelligence.currentSpeedKmh > 1 {
                        Label("\(Int(locationMonitor.intelligence.currentSpeedKmh)) km/h",
                              systemImage: "speedometer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !locationMonitor.isAuthorized {
                    Text("Location permission required. Enable in Settings → Privacy → Location.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                // Lookahead prediction
                if let prediction = locationMonitor.intelligence.lookaheadPrediction,
                   prediction.confidence >= 0.3 {
                    HStack(spacing: 4) {
                        switch prediction.expectedQuality {
                        case .poor, .bad:
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("\(prediction.expectedQuality.rawValue) connectivity in ~\(Int(prediction.minutesAhead)) min")
                                .foregroundColor(.orange)
                        case .excellent, .good:
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                            Text("Good connectivity ahead")
                                .foregroundColor(.green)
                        default:
                            EmptyView()
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        HStack(spacing: 0) {
            statItem(
                title: "Packet Loss",
                value: latencyMonitor.packetLossRatio.map { "\(Int($0 * 100))%" } ?? "--"
            )
            Divider().frame(height: 40)
            statItem(
                title: "Interface",
                value: networkMonitor.interfaceName.isEmpty ? "--" : networkMonitor.interfaceName
            )
            Divider().frame(height: 40)
            statItem(
                title: "Speed",
                value: locationMonitor.intelligence.currentSpeedKmh > 1
                    ? "\(Int(locationMonitor.intelligence.currentSpeedKmh)) km/h"
                    : "Stationary"
            )
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
