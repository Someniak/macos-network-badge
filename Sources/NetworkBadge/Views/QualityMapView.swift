// ---------------------------------------------------------
// QualityMapView.swift — Map showing network quality over GPS
//
// Displays a MapKit map with an Uber-style colored trail
// showing the travel path, with each segment colored by
// network quality:
//   - Green = Excellent/Good
//   - Yellow = Fair
//   - Orange = Poor
//   - Red = Bad
//
// Features a live pulsing position marker with bearing arrow,
// quality dots at measurement points, and trail rendering
// via MKMapView (NSViewRepresentable) for proper polylines.
// ---------------------------------------------------------

import MapKit
import SwiftUI

// MARK: - Quality Map View

/// The main map view showing GPS-tagged network quality measurements.
///
/// Each measurement appears as a colored circle on the map,
/// sized and colored by the latency quality at that location.
struct QualityMapView: View {

    /// The quality database to read records from
    let database: QualityDatabase

    /// The tile cache for offline map support
    let tileCache: TileCache

    /// Location monitor for live position updates
    @ObservedObject var locationMonitor: LocationMonitor

    /// Latency monitor for ping status
    @ObservedObject var latencyMonitor: LatencyMonitor

    /// Network monitor for connection info
    @ObservedObject var networkMonitor: NetworkMonitor

    /// Controller for opening the data browser window (macOS only)
    #if os(macOS)
    var dataBrowserController: DataBrowserWindowController?
    #endif

    /// Current user location (from LocationMonitor, live-updating)
    private var currentLatitude: Double? { locationMonitor.latitude }
    private var currentLongitude: Double? { locationMonitor.longitude }

    /// Current bearing in degrees (from LocationIntelligence, live-updating)
    private var currentBearing: Double { locationMonitor.intelligence.currentBearing }

    /// Records to display on the map
    @State private var records: [QualityRecord] = []

    /// Trail segments for the quality polyline
    @State private var segments: [TrailSegment] = []

    /// Map region — controls what's visible on the map.
    /// Uses coordinateRegion binding (macOS 13-compatible).
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 50.85, longitude: 4.35),  // Brussels default
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    /// Selected record (for detail popup)
    @State private var selectedRecord: QualityRecord?

    /// Time filter: how far back to show records
    @State private var timeFilter: TimeFilter = .allTime

    /// Total record count in database
    @State private var totalRecords: Int = 0

    /// Detected runs from loaded records
    @State private var runs: [Run] = []

    /// Selected run ID (nil = all runs)
    @State private var runFilter: Int? = nil

    /// Whether the initial region has been set (prevents resetting on incremental updates)
    @State private var hasSetInitialRegion: Bool = false

    /// Incremented to signal a programmatic region change to TrailMapView
    @State private var regionToken: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // ── Map ───────────────────────────────────────
            mapContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ── Controls Bar ──────────────────────────────
            controlsBar

            // ── Status Bar ──────────────────────────────────
            statusBar
        }
        .onAppear {
            loadRecords()
        }
        .onChange(of: locationMonitor.sessionRecordCount) { _ in
            loadRecords()
        }
    }

    // MARK: - Run Filtering

    /// Records filtered by the selected run
    private var filteredRecords: [QualityRecord] {
        guard let runID = runFilter,
              let run = runs.first(where: { $0.id == runID }) else {
            return records
        }
        return records.filter { run.recordIDs.contains($0.id) }
    }

    /// Segments filtered by the selected run (rebuild trail from filtered records)
    private var filteredSegments: [TrailSegment] {
        guard runFilter != nil else { return segments }
        return QualityTrailBuilder.buildTrail(from: filteredRecords)
    }

    // MARK: - Map Content

    /// The map with quality trail, annotations, and live marker.
    /// Uses TrailMapView (MKMapView via NSViewRepresentable) for
    /// proper polyline rendering with per-segment colors.
    @ViewBuilder
    private var mapContent: some View {
        TrailMapView(
            records: filteredRecords,
            segments: filteredSegments,
            currentLatitude: currentLatitude,
            currentLongitude: currentLongitude,
            currentBearing: currentBearing,
            region: $region,
            selectedRecord: $selectedRecord,
            regionToken: regionToken
        )
        .overlay(alignment: .topTrailing) {
            // Record count badge
            recordCountBadge
                .padding(8)
        }
        .overlay(alignment: .bottom) {
            // Selected record detail card
            if let record = selectedRecord {
                recordDetailCard(record)
                    .padding(8)
                    .transition(.move(edge: .bottom))
            }
        }
    }

    // MARK: - Record Count Badge

    /// Shows how many records are visible vs total
    private var recordCountBadge: some View {
        Text("\(filteredRecords.count) of \(totalRecords) records")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .cornerRadius(6)
    }

    // MARK: - Controls Bar

    /// Bottom bar with time and quality filters
    private var controlsBar: some View {
        HStack(spacing: 12) {
            // Time filter — segmented picker for quick time range selection
            Picker("Time", selection: $timeFilter) {
                ForEach(TimeFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .onChange(of: timeFilter) { _ in loadRecords() }

            // Run filter — select individual journeys
            Picker("Run", selection: $runFilter) {
                Text("All Runs").tag(nil as Int?)
                ForEach(runs) { run in
                    Text(runPickerLabel(run)).tag(run.id as Int?)
                }
            }
            .frame(width: 200)

            Spacer()

            #if os(macOS)
            // Data browser — opens the Excel-like record viewer
            if let controller = dataBrowserController {
                Button(action: { controller.showWindow() }) {
                    Image(systemName: "tablecells")
                }
                .buttonStyle(.bordered)
                .help("Browse all records")
            }
            #endif

            // Center on user — only shown when GPS is active
            if currentLatitude != nil && currentLongitude != nil {
                Button(action: centerOnUser) {
                    Image(systemName: "location")
                }
                .buttonStyle(.bordered)
                .help("Center on current location")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Status Bar

    /// Bottom status line showing live operational state
    private var statusBar: some View {
        HStack(spacing: 0) {
            // Location source
            Text(locationSourceLabel)

            Text(" · ").foregroundColor(.secondary.opacity(0.5))

            // Last ping
            Text(lastPingLabel)

            Text(" · ").foregroundColor(.secondary.opacity(0.5))

            // Connection
            Text(connectionLabel)

            Text(" · ").foregroundColor(.secondary.opacity(0.5))

            // Session count
            Text("\(locationMonitor.sessionRecordCount) records")

            // Speed
            Text(" · ").foregroundColor(.secondary.opacity(0.5))
            if locationMonitor.intelligence.isSpeedEstimated {
                Text("~\(Int(locationMonitor.intelligence.currentSpeedKmh)) km/h")
            } else {
                Text("\(Int(locationMonitor.intelligence.currentSpeedKmh)) km/h")
            }

            // Lookahead prediction
            if let prediction = locationMonitor.intelligence.lookaheadPrediction,
               prediction.confidence >= 0.3 {
                Text(" · ").foregroundColor(.secondary.opacity(0.5))
                switch prediction.expectedQuality {
                case .poor, .bad:
                    Text("\u{26A0} \(prediction.expectedQuality.rawValue) in ~\(Int(prediction.minutesAhead)) min")
                        .foregroundColor(.orange)
                case .excellent, .good:
                    Text("Good ahead")
                        .foregroundColor(.green)
                default:
                    EmptyView()
                }
            }

            Spacer()
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }

    /// Describes which location source is active
    private var locationSourceLabel: String {
        let gps = locationMonitor.gps2ip
        if !locationMonitor.isTrackingEnabled {
            return "Not tracking"
        }
        if !locationMonitor.isAuthorized {
            return "No authorization"
        }
        if gps.isConnected {
            let via = gps.activeEndpoint?.displayLabel ?? ""
            if let fix = gps.lastFixAt {
                let ago = Int(-fix.timeIntervalSinceNow)
                return "GPS2IP \(via) · fix \(ago)s ago"
            }
            return "GPS2IP \(via) · no fix yet"
        }
        if gps.isEnabled {
            if let err = gps.errorMessage {
                return "GPS2IP · \(err)"
            }
            return "GPS2IP · connecting…"
        }
        if locationMonitor.isTracking {
            return "CoreLocation"
        }
        return "Waiting…"
    }

    /// Describes the last ping measurement
    private var lastPingLabel: String {
        if latencyMonitor.isMeasuring {
            return "Measuring…"
        }
        if let latency = latencyMonitor.currentLatencyMs,
           let lastSample = latencyMonitor.samples.first {
            let ago = Int(-lastSample.timestamp.timeIntervalSinceNow)
            return "\(Int(latency)) ms · \(ago)s ago"
        }
        return "Idle"
    }

    /// Describes the current network connection
    private var connectionLabel: String {
        if !networkMonitor.isConnected {
            return "Disconnected"
        }
        let type = networkMonitor.connectionType.rawValue
        if let ssid = networkMonitor.wifiSSID {
            return "\(type) (\(ssid))"
        }
        return type
    }

    // MARK: - Record Detail Card

    /// Shows detailed information about a tapped quality measurement.
    /// Appears as a floating card at the bottom of the map.
    private func recordDetailCard(_ record: QualityRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Quality badge — colored label showing the quality level
                Text(record.quality)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(record.qualityLevel.swiftUIColor.opacity(0.2))
                    .cornerRadius(4)
                    .foregroundColor(record.qualityLevel.swiftUIColor)

                // Latency value (only for successful measurements)
                if record.wasSuccessful {
                    Text("\(Int(record.latencyMs)) ms")
                        .font(.body.monospacedDigit().bold())
                }

                Spacer()

                // Close button to dismiss the detail card
                Button(action: { selectedRecord = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                // Connection type with icon
                Label(record.connectionType, systemImage: connectionSymbol(for: record.connectionType))
                    .font(.caption)

                // WiFi network name (if applicable)
                if let ssid = record.wifiSSID {
                    Text(ssid)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Relative timestamp (e.g. "2 hours ago")
                Text(record.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // GPS coordinates and location source
            Text(String(format: "%.5f, %.5f (±%.0fm) — %@",
                        record.latitude, record.longitude,
                        record.locationAccuracy, record.locationSource))
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .frame(maxWidth: 400)
    }

    // MARK: - Data Loading

    /// Loads records from the database with current filters applied.
    /// Called on appear and whenever filters change.
    private func loadRecords() {
        let db = database
        let tFilter = timeFilter

        Task.detached {
            let count = db.recordCount()

            var allRecords: [QualityRecord]
            if let startDate = tFilter.startDate {
                allRecords = db.queryTimeRange(from: startDate, to: Date())
            } else {
                allRecords = db.queryAll()
            }

            let builtSegments = QualityTrailBuilder.buildTrail(from: allRecords)

            let visibleRecords = allRecords.filter { record in
                record.locationSourceLevel != .none &&
                (record.latitude != 0 && record.longitude != 0)
            }

            let detectedRuns = RunDetector.detectRuns(from: allRecords)

            await MainActor.run {
                totalRecords = count
                segments = builtSegments
                records = visibleRecords
                runs = detectedRuns
                if let selected = runFilter, !detectedRuns.contains(where: { $0.id == selected }) {
                    runFilter = nil
                }
                updateRegionIfNeeded()
            }
        }
    }

    /// Centers the map on the user's current GPS location
    private func centerOnUser() {
        if let lat = currentLatitude, let lon = currentLongitude {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            regionToken += 1
        }
    }

    /// Sets the map region once on first load. Subsequent reloads preserve
    /// the user's manual pan/zoom.
    private func updateRegionIfNeeded() {
        guard !hasSetInitialRegion else { return }

        if let lat = currentLatitude, let lon = currentLongitude {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            regionToken += 1
            hasSetInitialRegion = true
            return
        }

        guard !records.isEmpty else { return }

        let lats = records.map { $0.latitude }
        let lons = records.map { $0.longitude }

        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }

        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let spanLat = max((maxLat - minLat) * 1.3, 0.01)
        let spanLon = max((maxLon - minLon) * 1.3, 0.01)

        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
        )
        regionToken += 1
        hasSetInitialRegion = true
    }

    /// Formats a run label for the picker dropdown
    private func runPickerLabel(_ run: Run) -> String {
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        let start = tf.string(from: run.startTime)
        let end = tf.string(from: run.endTime)
        return "Run \(run.id) — \(start)–\(end) (\(run.recordCount))"
    }

    /// Returns the SF Symbol name for a connection type string.
    /// Maps ConnectionType raw values back to their icons.
    private func connectionSymbol(for type: String) -> String {
        switch type {
        case "WiFi": return "wifi"
        case "Ethernet": return "cable.connector"
        case "USB Tethering": return "cable.connector.horizontal"
        case "Cellular": return "antenna.radiowaves.left.and.right"
        default: return "network"
        }
    }
}

// MARK: - Time Filter

/// Filters records by how recently they were recorded.
/// Used in the map's control bar for quick time-range selection.
enum TimeFilter: CaseIterable {
    case lastHour
    case today
    case lastWeek
    case lastMonth
    case allTime

    /// Short label for the segmented picker
    var label: String {
        switch self {
        case .lastHour:  return "1h"
        case .today:     return "Today"
        case .lastWeek:  return "7d"
        case .lastMonth: return "30d"
        case .allTime:   return "All"
        }
    }

    /// The start date for this filter, or nil for "all time"
    var startDate: Date? {
        switch self {
        case .lastHour:  return Calendar.current.date(byAdding: .hour, value: -1, to: Date())
        case .today:     return Calendar.current.startOfDay(for: Date())
        case .lastWeek:  return Calendar.current.date(byAdding: .day, value: -7, to: Date())
        case .lastMonth: return Calendar.current.date(byAdding: .month, value: -1, to: Date())
        case .allTime:   return nil
        }
    }
}

// MARK: - Quality Filter

/// Filters records by quality level.
/// Used in the map's control bar to focus on problematic areas.
enum QualityFilter: CaseIterable {
    case all
    case excellent
    case good
    case fair
    case poor
    case bad

    /// Label for the dropdown picker
    var label: String {
        switch self {
        case .all:       return "All"
        case .excellent: return "Excellent"
        case .good:      return "Good"
        case .fair:      return "Fair"
        case .poor:      return "Poor"
        case .bad:       return "Bad"
        }
    }

    /// Returns true if a quality level matches this filter.
    /// Cumulative: selecting "Fair" shows Excellent + Good + Fair
    /// (all levels up to and including the selected one).
    func matches(_ quality: LatencyQuality) -> Bool {
        switch self {
        case .all:       return true
        case .excellent: return quality == .excellent
        case .good:      return quality == .excellent || quality == .good
        case .fair:      return quality == .excellent || quality == .good || quality == .fair
        case .poor:      return quality == .excellent || quality == .good || quality == .fair || quality == .poor
        case .bad:       return true  // all levels including bad
        }
    }
}
