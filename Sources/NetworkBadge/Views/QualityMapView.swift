// ---------------------------------------------------------
// QualityMapView.swift — Map showing network quality over GPS
//
// Displays a MapKit map with colored dots at each location
// where a network quality measurement was recorded. Colors
// match the app's quality scheme:
//   - Green = Excellent/Good
//   - Yellow = Fair
//   - Orange = Poor
//   - Red = Bad
//
// The map uses cached tiles for offline viewing and supports
// filtering by time range and quality level.
//
// Uses the macOS 13-compatible Map API (coordinateRegion +
// annotationItems) to match the project's deployment target.
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

    /// Current user location (from LocationMonitor)
    let currentLatitude: Double?
    let currentLongitude: Double?

    /// Records to display on the map
    @State private var records: [QualityRecord] = []

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

    /// Quality filter: minimum quality to show
    @State private var qualityFilter: QualityFilter = .all

    /// Total record count in database
    @State private var totalRecords: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // ── Map ───────────────────────────────────────
            mapContent

            // ── Controls Bar ──────────────────────────────
            controlsBar
        }
        .onAppear {
            loadRecords()
        }
    }

    // MARK: - Map Content

    /// The map with quality annotations overlaid.
    /// Uses the macOS 13-compatible Map(coordinateRegion:annotationItems:) API.
    @ViewBuilder
    private var mapContent: some View {
        Map(coordinateRegion: $region, annotationItems: records) { record in
            // Each record is shown as a colored circle at its GPS coordinates
            MapAnnotation(
                coordinate: CLLocationCoordinate2D(
                    latitude: record.latitude,
                    longitude: record.longitude
                )
            ) {
                qualityDot(for: record)
                    .onTapGesture {
                        selectedRecord = record
                    }
            }
        }
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

    // MARK: - Quality Dot

    /// A colored circle representing a quality measurement on the map.
    /// Size indicates whether measurement was successful.
    private func qualityDot(for record: QualityRecord) -> some View {
        Circle()
            .fill(record.qualityLevel.swiftUIColor.opacity(0.8))
            .frame(width: dotSize(for: record), height: dotSize(for: record))
            .overlay(
                Circle()
                    .stroke(record.qualityLevel.swiftUIColor, lineWidth: 1)
            )
            .shadow(color: record.qualityLevel.swiftUIColor.opacity(0.4), radius: 3)
    }

    /// Dot size: successful measurements are larger than failed ones
    private func dotSize(for record: QualityRecord) -> CGFloat {
        record.wasSuccessful ? 12 : 8
    }

    // MARK: - Record Count Badge

    /// Shows how many records are visible vs total
    private var recordCountBadge: some View {
        Text("\(records.count) of \(totalRecords) records")
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

            Spacer()

            // Quality filter — dropdown to show only poor/bad areas
            Picker("Quality", selection: $qualityFilter) {
                ForEach(QualityFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .frame(width: 120)
            .onChange(of: qualityFilter) { _ in loadRecords() }

            // Refresh button — reload records from database
            Button(action: loadRecords) {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload records from database")

            // Center on user — only shown when GPS is active
            if currentLatitude != nil && currentLongitude != nil {
                Button(action: centerOnUser) {
                    Image(systemName: "location")
                }
                .help("Center on current location")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
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

            // GPS coordinates — useful for debugging and analysis
            Text(String(format: "%.5f, %.5f (±%.0fm)",
                        record.latitude, record.longitude, record.locationAccuracy))
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
        totalRecords = database.recordCount()

        var filtered: [QualityRecord]

        // Apply time filter
        if let startDate = timeFilter.startDate {
            filtered = database.queryTimeRange(from: startDate, to: Date())
        } else {
            filtered = database.queryAll()
        }

        // Apply quality filter
        if qualityFilter != .all {
            filtered = filtered.filter { record in
                qualityFilter.matches(quality: record.quality)
            }
        }

        records = filtered
        updateRegionIfNeeded()
    }

    /// Centers the map on the user's current GPS location
    private func centerOnUser() {
        if let lat = currentLatitude, let lon = currentLongitude {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
    }

    /// Sets initial map region based on available data.
    /// Priority: current location > fit all records > Brussels default
    private func updateRegionIfNeeded() {
        // If we have a current location, center there
        if let lat = currentLatitude, let lon = currentLongitude {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            return
        }

        // Otherwise, fit all records in view
        guard !records.isEmpty else { return }

        let lats = records.map { $0.latitude }
        let lons = records.map { $0.longitude }

        let centerLat = (lats.min()! + lats.max()!) / 2
        let centerLon = (lons.min()! + lons.max()!) / 2
        let spanLat = max((lats.max()! - lats.min()!) * 1.3, 0.01)
        let spanLon = max((lons.max()! - lons.min()!) * 1.3, 0.01)

        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
        )
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
    case poorAndBelow
    case badOnly

    /// Label for the dropdown picker
    var label: String {
        switch self {
        case .all:           return "All"
        case .poorAndBelow:  return "Poor+"
        case .badOnly:       return "Bad only"
        }
    }

    /// Returns true if a record's quality string matches this filter
    func matches(quality: String) -> Bool {
        switch self {
        case .all:
            return true
        case .poorAndBelow:
            return quality == "Poor" || quality == "Bad"
        case .badOnly:
            return quality == "Bad"
        }
    }
}
