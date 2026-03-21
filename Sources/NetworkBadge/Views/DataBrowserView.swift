// ---------------------------------------------------------
// DataBrowserView.swift — Excel-like record viewer
//
// A Table-based view showing all QualityRecord fields with
// sorting, filtering, search, and CSV export.
// ---------------------------------------------------------

#if os(macOS)
import AppKit
import SwiftUI

struct DataBrowserView: View {

    let database: QualityDatabase

    @State private var records: [QualityRecord] = []
    @State private var totalRecords: Int = 0
    @State private var searchText: String = ""
    @State private var timeFilter: TimeFilter = .allTime
    @State private var qualityFilter: QualityFilter = .all
    @State private var sortOrder = [KeyPathComparator(\QualityRecord.timestamp, order: .reverse)]
    @State private var runs: [Run] = []
    @State private var runFilter: Int? = nil
    @State private var runLookup: [UUID: Int] = [:]

    private var filteredRecords: [QualityRecord] {
        var result = records

        // Run filter
        if let runID = runFilter, let run = runs.first(where: { $0.id == runID }) {
            result = result.filter { run.recordIDs.contains($0.id) }
        }

        // Quality filter
        if qualityFilter != .all {
            result = result.filter { qualityFilter.matches($0.qualityLevel) }
        }

        // Text search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { record in
                record.connectionType.lowercased().contains(query)
                || record.quality.lowercased().contains(query)
                || (record.wifiSSID?.lowercased().contains(query) ?? false)
                || record.locationSource.lowercased().contains(query)
            }
        }

        return result.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            // Table
            Table(filteredRecords, sortOrder: $sortOrder) {
                TableColumn("Time", value: \.timestamp) { record in
                    Text(record.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute().second())
                        .monospacedDigit()
                }
                .width(min: 100, ideal: 140)

                TableColumn("Latency", value: \.latencyMs) { record in
                    if record.wasSuccessful {
                        Text("\(Int(record.latencyMs)) ms")
                            .monospacedDigit()
                            .foregroundColor(record.qualityLevel.swiftUIColor)
                    } else {
                        Text("Timeout")
                            .foregroundColor(.red)
                    }
                }
                .width(min: 50, ideal: 70)

                TableColumn("Jitter") { record in
                    if let jitter = record.jitter {
                        Text("\(Int(jitter)) ms")
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }
                .width(min: 40, ideal: 60)

                TableColumn("Pkt Loss") { record in
                    if let loss = record.packetLossRatio {
                        Text("\(Int(loss * 100))%")
                            .monospacedDigit()
                            .foregroundColor(loss > 0.3 ? .red : loss > 0.1 ? .orange : .primary)
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }
                .width(min: 40, ideal: 60)

                TableColumn("Type", value: \.connectionType) { record in
                    Text(record.connectionType)
                }
                .width(min: 60, ideal: 80)

                TableColumn("WiFi") { record in
                    if let ssid = record.wifiSSID {
                        let rssiStr = record.wifiRSSI.map { " \($0)" } ?? ""
                        Text("\(ssid)\(rssiStr)")
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }
                .width(min: 80, ideal: 120)

                TableColumn("Location") { record in
                    Text("\(String(format: "%.4f", record.latitude)), \(String(format: "%.4f", record.longitude)) ±\(Int(record.locationAccuracy))m")
                        .monospacedDigit()
                }
                .width(min: 140, ideal: 200)

                TableColumn("Speed") { record in
                    if let speed = record.speedKmh {
                        Text("\(Int(speed)) km/h")
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }
                .width(min: 50, ideal: 70)

                TableColumn("Alt") { record in
                    if let alt = record.altitude {
                        Text("\(Int(alt))m")
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }
                .width(min: 40, ideal: 55)

                TableColumn("Course Δ") { record in
                    if let rate = record.courseChangeRate {
                        Text("\(String(format: "%.1f", rate))°/s")
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }
                .width(min: 45, ideal: 60)
            }

            // Status bar
            statusBar
        }
        .onAppear { loadRecords() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search SSID, type, quality…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: 220)

            // Time filter
            Picker("Time", selection: $timeFilter) {
                ForEach(TimeFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .frame(width: 100)
            .onChange(of: timeFilter) { _ in loadRecords() }

            // Quality filter
            Picker("Quality", selection: $qualityFilter) {
                ForEach(QualityFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .frame(width: 110)

            // Run filter
            Picker("Run", selection: $runFilter) {
                Text("All Runs").tag(nil as Int?)
                ForEach(runs) { run in
                    Text(runPickerLabel(run)).tag(run.id as Int?)
                }
            }
            .frame(width: 180)

            Spacer()

            // Export CSV
            Button(action: exportCSV) {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)

            // Refresh
            Button(action: loadRecords) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("Reload records")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            let filtered = filteredRecords.count
            let runCount = runs.count
            let runText = runCount == 1 ? "1 run" : "\(runCount) runs"
            Text("Showing \(formatted(filtered)) of \(formatted(totalRecords)) records · \(runText)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }

    // MARK: - Data Loading

    private func loadRecords() {
        let db = database
        let tFilter = timeFilter

        Task.detached {
            let count = db.recordCount()

            let loaded: [QualityRecord]
            if let startDate = tFilter.startDate {
                loaded = db.queryTimeRange(from: startDate, to: Date())
            } else {
                loaded = db.queryAll()
            }

            let detectedRuns = RunDetector.detectRuns(from: loaded)

            let lookup: [UUID: Int] = {
                var dict: [UUID: Int] = [:]
                for run in detectedRuns {
                    for id in run.recordIDs {
                        dict[id] = run.id
                    }
                }
                return dict
            }()

            await MainActor.run {
                totalRecords = count
                records = loaded
                runs = detectedRuns
                runLookup = lookup
                // Reset run filter if selected run no longer exists
                if let selected = runFilter, !detectedRuns.contains(where: { $0.id == selected }) {
                    runFilter = nil
                }
            }
        }
    }

    // MARK: - CSV Export

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "network-quality-\(dateStamp()).csv"
        panel.title = "Export Records as CSV"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let rows = filteredRecords
        let lookup = runLookup
        var csv = "Time,Run,Latency (ms),Successful,Quality,Type,SSID,RSSI (dBm),Latitude,Longitude,Accuracy (m),Source,Speed (km/h),Altitude (m),Jitter (ms),Packet Loss,Course Change Rate (deg/s)\n"

        let formatter = ISO8601DateFormatter()
        for r in rows {
            let ssid = r.wifiSSID?.replacingOccurrences(of: ",", with: ";") ?? ""
            let rssi = r.wifiRSSI.map { String($0) } ?? ""
            let runNum = lookup[r.id].map { String($0) } ?? ""
            let speed = r.speedKmh.map { String(Int($0)) } ?? ""
            let altitude = r.altitude.map { String(format: "%.1f", $0) } ?? ""
            let jitter = r.jitter.map { String(format: "%.1f", $0) } ?? ""
            let packetLoss = r.packetLossRatio.map { String(format: "%.2f", $0) } ?? ""
            let courseChange = r.courseChangeRate.map { String(format: "%.2f", $0) } ?? ""
            csv += "\(formatter.string(from: r.timestamp)),\(runNum),\(r.latencyMs),\(r.wasSuccessful),\(r.quality),\(r.connectionType),\(ssid),\(rssi),\(r.latitude),\(r.longitude),\(r.locationAccuracy),\(r.locationSource),\(speed),\(altitude),\(jitter),\(packetLoss),\(courseChange)\n"
        }

        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func formatted(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func runPickerLabel(_ run: Run) -> String {
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        let start = tf.string(from: run.startTime)
        let end = tf.string(from: run.endTime)
        return "Run \(run.id) — \(start)–\(end)"
    }
}
#endif
