// ---------------------------------------------------------
// DataListView.swift — iOS record browser
//
// SwiftUI List replacement for the macOS AppKit Table-based
// DataBrowserView. Shows quality records with search,
// time filtering, and CSV export via share sheet.
// ---------------------------------------------------------

#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

struct DataListView: View {

    let database: QualityDatabase

    @State private var records: [QualityRecord] = []
    @State private var totalRecords: Int = 0
    @State private var searchText: String = ""
    @State private var timeFilter: TimeFilter = .allTime
    @State private var runs: [Run] = []
    @State private var runFilter: Int? = nil
    @State private var showingShareSheet = false
    @State private var csvURL: URL?

    private var filteredRecords: [QualityRecord] {
        var result = records

        // Run filter
        if let runID = runFilter, let run = runs.first(where: { $0.id == runID }) {
            result = result.filter { run.recordIDs.contains($0.id) }
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

        return result
    }

    var body: some View {
        NavigationStack {
            List(filteredRecords) { record in
                RecordRow(record: record)
            }
            .searchable(text: $searchText, prompt: "Search SSID, type, quality…")
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(TimeFilter.allCases, id: \.self) { filter in
                            Button(action: {
                                timeFilter = filter
                                loadRecords()
                            }) {
                                HStack {
                                    Text(filter.label)
                                    if timeFilter == filter {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(timeFilter.label, systemImage: "clock")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: exportCSV) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .onAppear { loadRecords() }
            .overlay {
                if filteredRecords.isEmpty {
                    ContentUnavailableView(
                        "No Records",
                        systemImage: "chart.line.downtrend.xyaxis",
                        description: Text("Start GPS tracking to record network quality measurements as you move.")
                    )
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = csvURL {
                    ShareSheet(items: [url])
                }
            }
        }
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

            await MainActor.run {
                totalRecords = count
                records = loaded
                runs = detectedRuns
                if let selected = runFilter, !detectedRuns.contains(where: { $0.id == selected }) {
                    runFilter = nil
                }
            }
        }
    }

    // MARK: - CSV Export

    private func exportCSV() {
        let rows = filteredRecords
        var csv = "Time,Latency (ms),Successful,Quality,Type,SSID,RSSI (dBm),Latitude,Longitude,Accuracy (m),Source,Speed (km/h)\n"

        let formatter = ISO8601DateFormatter()
        for r in rows {
            let ssid = r.wifiSSID?.replacingOccurrences(of: ",", with: ";") ?? ""
            let rssi = r.wifiRSSI.map { String($0) } ?? ""
            let speed = r.speedKmh.map { String(Int($0)) } ?? ""
            csv += "\(formatter.string(from: r.timestamp)),\(r.latencyMs),\(r.wasSuccessful),\(r.quality),\(r.connectionType),\(ssid),\(rssi),\(r.latitude),\(r.longitude),\(r.locationAccuracy),\(r.locationSource),\(speed)\n"
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("network-quality-\(dateStamp()).csv")
        try? csv.write(to: tempURL, atomically: true, encoding: .utf8)
        csvURL = tempURL
        showingShareSheet = true
    }

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// MARK: - Record Row

private struct RecordRow: View {
    let record: QualityRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Quality badge
                Text(record.quality)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(record.qualityLevel.swiftUIColor.opacity(0.2))
                    .cornerRadius(4)
                    .foregroundColor(record.qualityLevel.swiftUIColor)

                // Latency
                if record.wasSuccessful {
                    Text("\(Int(record.latencyMs)) ms")
                        .font(.body.monospacedDigit().bold())
                } else {
                    Text("Timeout")
                        .font(.body.bold())
                        .foregroundColor(.red)
                }

                Spacer()

                // Connection type
                Label(record.connectionType,
                      systemImage: connectionSymbol(for: record.connectionType))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                // Time
                Text(record.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let ssid = record.wifiSSID {
                    Text(ssid)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let speed = record.speedKmh, speed > 1 {
                    Text("\(Int(speed)) km/h")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func connectionSymbol(for type: String) -> String {
        switch type {
        case "WiFi": return "wifi"
        case "Ethernet": return "cable.connector"
        case "Cellular": return "antenna.radiowaves.left.and.right"
        default: return "network"
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
