// ---------------------------------------------------------
// LocationIntelligence.swift — Smart location processing
//
// Self-contained module that handles all intelligent location
// processing: Kalman filtering, outlier detection, backpropagation,
// speed/bearing estimation, road snapping, and IP geolocation.
//
// Designed for train travel where MacBook Wi-Fi positioning
// is noisy, intermittent, or unavailable. Uses Uber-style
// techniques to produce smooth, accurate location trails.
// ---------------------------------------------------------

import Combine
import CoreLocation
import Foundation
import MapKit

/// Processes raw GPS/Wi-Fi locations into smooth, reliable coordinates.
///
/// Usage:
///   let intelligence = LocationIntelligence(database: db)
///   let smoothed = intelligence.kalmanSmooth(rawLocation)
///   let valid = intelligence.validateLocation(smoothed)
///
final class LocationIntelligence: ObservableObject {

    // MARK: - Settings (persisted to UserDefaults)

    /// Maximum acceptable accuracy in meters. Readings beyond this are rejected.
    @Published var accuracyThreshold: CLLocationDistance = 2000.0 {
        didSet { UserDefaults.standard.set(accuracyThreshold, forKey: "liAccuracyThreshold") }
    }

    /// Whether to fall back to IP geolocation when CoreLocation fails.
    @Published var ipGeolocationEnabled: Bool = false {
        didSet { UserDefaults.standard.set(ipGeolocationEnabled, forKey: "liIPGeolocationEnabled") }
    }

    /// Maximum time gap (seconds) for backpropagation interpolation.
    /// Gaps larger than this are considered separate trips.
    @Published var maxInterpolationGap: TimeInterval = 300 {
        didSet { UserDefaults.standard.set(maxInterpolationGap, forKey: "liMaxInterpolationGap") }
    }

    /// Maximum plausible speed in m/s. Points implying faster travel are outliers.
    /// Default 90 m/s = 324 km/h (covers TGV/ICE high-speed trains).
    @Published var maxReasonableSpeed: Double = 90.0 {
        didSet { UserDefaults.standard.set(maxReasonableSpeed, forKey: "liMaxReasonableSpeed") }
    }

    /// Whether to show the quality trail on the map.
    @Published var showTrail: Bool = true {
        didSet { UserDefaults.standard.set(showTrail, forKey: "liShowTrail") }
    }

    // MARK: - Public State

    /// Current bearing in degrees from north (0-360). Updated on each location.
    @Published private(set) var currentBearing: Double = 0

    /// Current estimated speed in m/s, computed from recent location buffer.
    /// Thread-safe — acquires the internal queue.
    var estimatedSpeed: Double {
        queue.sync { _estimatedSpeed }
    }

    /// Non-locking speed calculation for use inside `queue.sync` blocks.
    private var _estimatedSpeed: Double {
        guard recentLocations.count >= 2,
              let first = recentLocations.first,
              let last = recentLocations.last else { return 0 }
        let elapsed = last.time.timeIntervalSince(first.time)
        guard elapsed > 0 else { return 0 }
        return last.location.distance(from: first.location) / elapsed
    }

    // MARK: - Dependencies

    private let database: QualityDatabase

    /// Serial queue protecting all mutable state below. LocationIntelligence
    /// is called from CLLocationManager's delegate thread, the main thread
    /// (stationary poll), and Swift concurrency (IP geolocation).
    private let queue = DispatchQueue(label: "LocationIntelligence")

    // MARK: - Kalman Filter State (access on `queue` only)

    private var kalmanLat: Double = 0
    private var kalmanLon: Double = 0
    private var kalmanVariance: Double = 1e6  // high initial uncertainty
    private var kalmanInitialized = false

    // MARK: - Backpropagation State (access on `queue` only)

    /// Last known good location (anchor for interpolation)
    private(set) var lastKnownLocation: CLLocation?
    private(set) var lastKnownTime: Date?

    /// Records waiting for a GPS fix to determine their position
    private var pendingRecords: [QualityRecord] = []

    // MARK: - IP Geolocation State (access on `queue` only)

    private var lastIPLookupTime: Date?

    // MARK: - Speed/Bearing Buffer (access on `queue` only)

    /// Rolling buffer of recent locations for speed estimation
    private var recentLocations: [(location: CLLocation, time: Date)] = []

    // MARK: - Initialization

    init(database: QualityDatabase) {
        self.database = database
        loadSettings()
    }

    private func loadSettings() {
        let threshold = UserDefaults.standard.double(forKey: "liAccuracyThreshold")
        if threshold > 0 { accuracyThreshold = threshold }

        if UserDefaults.standard.object(forKey: "liIPGeolocationEnabled") != nil {
            ipGeolocationEnabled = UserDefaults.standard.bool(forKey: "liIPGeolocationEnabled")
        }

        let gap = UserDefaults.standard.double(forKey: "liMaxInterpolationGap")
        if gap > 0 { maxInterpolationGap = gap }

        let speed = UserDefaults.standard.double(forKey: "liMaxReasonableSpeed")
        if speed > 0 { maxReasonableSpeed = speed }

        if UserDefaults.standard.object(forKey: "liShowTrail") != nil {
            showTrail = UserDefaults.standard.bool(forKey: "liShowTrail")
        }
    }

    // MARK: - Kalman Filter

    /// Smooth a raw GPS reading using a simple 1D Kalman filter.
    /// Reduces noise from Wi-Fi positioning so the map trail doesn't zigzag.
    func kalmanSmooth(_ location: CLLocation) -> CLLocation {
        queue.sync {
            let accuracy = max(location.horizontalAccuracy, 1.0)
            let measurementVariance = accuracy * accuracy

            if !kalmanInitialized {
                kalmanLat = location.coordinate.latitude
                kalmanLon = location.coordinate.longitude
                kalmanVariance = measurementVariance
                kalmanInitialized = true
                return location
            }

            // Predict step: increase uncertainty based on movement
            let processNoise = max(_estimatedSpeed * 0.1, 0.0001)
            kalmanVariance += processNoise

            // Update step: blend prediction with measurement
            let kalmanGain = kalmanVariance / (kalmanVariance + measurementVariance)
            kalmanLat += kalmanGain * (location.coordinate.latitude - kalmanLat)
            kalmanLon += kalmanGain * (location.coordinate.longitude - kalmanLon)
            kalmanVariance *= (1.0 - kalmanGain)

            return CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: kalmanLat, longitude: kalmanLon),
                altitude: location.altitude,
                horizontalAccuracy: sqrt(kalmanVariance),
                verticalAccuracy: location.verticalAccuracy,
                timestamp: location.timestamp
            )
        }
    }

    /// Reset the Kalman filter (e.g. when tracking restarts).
    func resetKalman() {
        queue.sync {
            kalmanInitialized = false
            kalmanVariance = 1e6
        }
    }

    // MARK: - Accuracy Classification

    /// Determine whether a location is accurate enough to record,
    /// and classify its source quality.
    func shouldRecord(location: CLLocation) -> (accept: Bool, source: LocationSource) {
        guard location.horizontalAccuracy >= 0 else { return (false, .none) }
        if location.horizontalAccuracy <= 200 { return (true, .coreLocation) }
        if location.horizontalAccuracy <= accuracyThreshold { return (true, .lowAccuracy) }
        return (false, .none)
    }

    // MARK: - Outlier Detection

    /// Check if a location is physically possible given the time since last known position.
    /// Returns nil if the point is an outlier (teleportation).
    func validateLocation(_ location: CLLocation) -> CLLocation? {
        queue.sync {
            guard let last = lastKnownLocation, let lastTime = lastKnownTime else {
                return location  // First location — accept
            }

            let elapsed = location.timestamp.timeIntervalSince(lastTime)
            guard elapsed > 0 else { return location }

            let distance = location.distance(from: last)
            let speed = distance / elapsed

            if speed > maxReasonableSpeed {
                return nil  // Physically impossible — reject
            }
            return location
        }
    }

    // MARK: - Bearing

    /// Update the current bearing based on movement between two locations.
    /// Must be called on the main thread.
    func updateBearing(from oldLocation: CLLocation, to newLocation: CLLocation) {
        let lat1 = oldLocation.coordinate.latitude * .pi / 180
        let lat2 = newLocation.coordinate.latitude * .pi / 180
        let dLon = (newLocation.coordinate.longitude - oldLocation.coordinate.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        var bearing = atan2(y, x) * 180 / .pi
        if bearing < 0 { bearing += 360 }
        currentBearing = bearing
    }

    // MARK: - Anchor Management

    /// Record a validated location as the latest anchor point.
    /// Updates speed buffer and bearing. Must be called on the main thread.
    func recordAnchor(_ location: CLLocation) {
        if let prev = queue.sync(execute: { lastKnownLocation }) {
            updateBearing(from: prev, to: location)
        }
        queue.sync {
            let time = location.timestamp
            recentLocations.append((location: location, time: time))
            if recentLocations.count > 10 { recentLocations.removeFirst() }
            lastKnownLocation = location
            lastKnownTime = time
        }
    }

    // MARK: - Backpropagation

    /// Buffer a record that has no GPS fix, for later interpolation.
    func bufferRecord(_ record: QualityRecord) {
        queue.sync {
            pendingRecords.append(record)
            if pendingRecords.count > 50 { pendingRecords.removeFirst() }
        }
    }

    /// When a new valid GPS fix arrives, interpolate positions for all buffered records.
    /// Uses linear interpolation between the last anchor and the new location,
    /// proportional to each record's timestamp.
    func backpropagate(newLocation: CLLocation) {
        queue.sync {
            guard !pendingRecords.isEmpty else { return }

            guard let anchorLocation = lastKnownLocation, let anchorTime = lastKnownTime else {
                // No start anchor — assign all pending to the new location
                _flushPendingAt(location: newLocation)
                return
            }

            let endTime = newLocation.timestamp
            let totalDuration = endTime.timeIntervalSince(anchorTime)

            guard totalDuration > 0, totalDuration <= maxInterpolationGap else {
                // Gap too large — discard pending (unreliable interpolation)
                pendingRecords.removeAll()
                return
            }

            let totalDistance = newLocation.distance(from: anchorLocation)

            for record in pendingRecords {
                let t = max(0, min(1, record.timestamp.timeIntervalSince(anchorTime) / totalDuration))

                let lat = anchorLocation.coordinate.latitude +
                    t * (newLocation.coordinate.latitude - anchorLocation.coordinate.latitude)
                let lon = anchorLocation.coordinate.longitude +
                    t * (newLocation.coordinate.longitude - anchorLocation.coordinate.longitude)

                let estimatedAccuracy = max(
                    anchorLocation.horizontalAccuracy,
                    newLocation.horizontalAccuracy,
                    totalDistance * 0.1
                )

                database.update(
                    id: record.id,
                    latitude: lat,
                    longitude: lon,
                    locationAccuracy: estimatedAccuracy,
                    locationSource: LocationSource.interpolated.rawValue
                )
            }
            pendingRecords.removeAll()
        }
    }

    /// Flush pending records by assigning them all to a single location.
    /// Must be called on `queue`.
    private func _flushPendingAt(location: CLLocation) {
        for record in pendingRecords {
            database.update(
                id: record.id,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                locationAccuracy: location.horizontalAccuracy,
                locationSource: LocationSource.interpolated.rawValue
            )
        }
        pendingRecords.removeAll()
    }

    /// Discard all pending records (called when tracking stops).
    func flushOnStop() {
        queue.sync { pendingRecords.removeAll() }
    }

    /// Number of records currently awaiting backpropagation.
    var pendingCount: Int { queue.sync { pendingRecords.count } }

    // MARK: - Road/Rail Snapping

    /// Snap interpolated points to actual roads using MKDirections.
    /// Called after backpropagation for segments with 3+ interpolated points.
    /// Falls back gracefully if network is unavailable.
    func snapToRoute(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) async -> [CLLocationCoordinate2D]? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        guard let response = try? await directions.calculate(),
              let route = response.routes.first else { return nil }

        let pointCount = route.polyline.pointCount
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }

    // MARK: - IP Geolocation Fallback

    /// Query an IP geolocation API for approximate city-level coordinates.
    /// Rate-limited to 1 request per 60 seconds.
    func fetchIPGeolocation() async -> (latitude: Double, longitude: Double)? {
        let shouldFetch: Bool = queue.sync {
            if let last = lastIPLookupTime, Date().timeIntervalSince(last) < 60 {
                return false  // Rate limited
            }
            return true
        }
        guard shouldFetch else { return nil }

        guard let url = URL(string: "https://ipapi.co/json/") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lat = json["latitude"] as? Double,
                  let lon = json["longitude"] as? Double else { return nil }
            queue.sync { lastIPLookupTime = Date() }
            return (lat, lon)
        } catch {
            return nil
        }
    }
}
