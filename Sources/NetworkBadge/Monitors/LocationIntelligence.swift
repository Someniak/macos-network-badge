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

    /// Spatial lookahead prediction: expected quality ahead based on historical data.
    @Published private(set) var lookaheadPrediction: QualityPrediction? = nil

    /// Current travel speed in km/h.
    /// Uses direct GPS speed when available, otherwise calculated from position deltas.
    @Published private(set) var currentSpeedKmh: Double = 0

    /// Whether the current speed is estimated from position deltas + Kalman smoothing
    /// rather than a direct GPS speed reading.
    @Published private(set) var isSpeedEstimated: Bool = true

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
        // If the most recent fix is stale (>10s), we've stopped moving
        guard -last.time.timeIntervalSinceNow < 10 else { return 0 }
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

    /// Timer that decays `currentSpeedKmh` toward zero when no new fixes arrive
    private var speedDecayTimer: Timer?

    // MARK: - Course Change Rate (access on `queue` only)

    /// Rolling buffer of recent bearings for course change rate calculation (last 30s)
    private var recentBearings: [(date: Date, bearing: Double)] = []

    // MARK: - Initialization

    init(database: QualityDatabase) {
        self.database = database
        loadSettings()
        startSpeedDecay()
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

    /// Periodically decay `currentSpeedKmh` toward zero when no new fixes arrive.
    private func startSpeedDecay() {
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let raw = self.estimatedSpeed * 3.6
            if raw < 1 {
                // Buffer is stale or barely moving — decay quickly to zero
                self.currentSpeedKmh = self.currentSpeedKmh * 0.5
                if self.currentSpeedKmh < 0.5 {
                    self.currentSpeedKmh = 0
                    if self.lookaheadPrediction != nil {
                        self.lookaheadPrediction = nil
                    }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        speedDecayTimer = timer
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

        // Track bearing changes for courseChangeRate
        let now = Date()
        queue.sync {
            recentBearings.append((date: now, bearing: bearing))
            let cutoff = now.addingTimeInterval(-30)
            recentBearings.removeAll { $0.date < cutoff }
        }
    }

    // MARK: - Course Change Rate

    /// Rate of bearing change in degrees per second over the last 30 seconds.
    /// High values correlate with winding roads/tracks and frequent tower handoffs.
    /// Returns nil if fewer than 2 entries or time span < 5s.
    var courseChangeRate: Double? {
        queue.sync {
            guard recentBearings.count >= 2,
                  let first = recentBearings.first,
                  let last = recentBearings.last else { return nil }
            let span = last.date.timeIntervalSince(first.date)
            guard span >= 5 else { return nil }

            var totalDelta = 0.0
            for i in 1..<recentBearings.count {
                var delta = abs(recentBearings[i].bearing - recentBearings[i - 1].bearing)
                if delta > 180 { delta = 360 - delta }
                totalDelta += delta
            }
            return totalDelta / span
        }
    }

    // MARK: - Spatial Lookahead Prediction

    /// Predict network quality ahead based on historical records near the projected position.
    /// Projects position forward 2 minutes at current speed/bearing and queries nearby records.
    func refreshPrediction() {
        let speed = currentSpeedKmh
        let bearing = currentBearing
        let location: CLLocation? = queue.sync { lastKnownLocation }

        guard speed >= 5, let loc = location else {
            DispatchQueue.main.async { self.lookaheadPrediction = nil }
            return
        }

        let minutesAhead = 2.0
        let distanceMeters = (speed / 3.6) * (minutesAhead * 60)
        let projected = CoordinateUtils.projectCoordinate(
            from: loc.coordinate, distance: distanceMeters, bearing: bearing
        )

        // 500m radius → lat/lon bounding box
        let radiusMeters = 500.0
        let latDelta = radiusMeters / 111_000.0
        let lonDelta = radiusMeters / (111_000.0 * cos(projected.latitude * .pi / 180))

        let records = database.queryInRegion(
            minLat: projected.latitude - latDelta,
            maxLat: projected.latitude + latDelta,
            minLon: projected.longitude - lonDelta,
            maxLon: projected.longitude + lonDelta
        )

        guard !records.isEmpty else {
            DispatchQueue.main.async { self.lookaheadPrediction = nil }
            return
        }

        // Weighted average: recent records count more (exponential decay by age)
        let now = Date()
        var weightedSum = 0.0
        var totalWeight = 0.0

        for record in records {
            let ageDays = now.timeIntervalSince(record.timestamp) / 86400.0
            let weight = exp(-ageDays / 7.0)  // half-life ~5 days
            let latency = record.wasSuccessful ? record.latencyMs : 1000.0
            weightedSum += latency * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else {
            DispatchQueue.main.async { self.lookaheadPrediction = nil }
            return
        }

        let avgLatency = weightedSum / totalWeight
        let quality = LatencyQuality.from(latencyMs: avgLatency)
        let confidence = min(Double(records.count) / 10.0, 1.0)

        let prediction = QualityPrediction(
            expectedQuality: quality,
            confidence: confidence,
            minutesAhead: minutesAhead,
            sampleCount: records.count,
            averageLatencyMs: avgLatency
        )

        DispatchQueue.main.async { self.lookaheadPrediction = prediction }
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
        // Prefer direct GPS speed (>= 0 means valid); fall back to position-delta calculation
        let rawSpeed: Double
        if location.speed >= 0 {
            rawSpeed = location.speed * 3.6
            isSpeedEstimated = false
        } else {
            rawSpeed = estimatedSpeed * 3.6
            isSpeedEstimated = true
        }
        if currentSpeedKmh == 0 {
            currentSpeedKmh = rawSpeed
        } else {
            // Exponential moving average — 0.3 weighting on new sample smooths out GPS jitter
            currentSpeedKmh = currentSpeedKmh * 0.7 + rawSpeed * 0.3
        }

        // Refresh spatial lookahead prediction on background queue
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.refreshPrediction()
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

            guard totalDuration > 0 else {
                pendingRecords.removeAll()
                return
            }

            let totalDistance = newLocation.distance(from: anchorLocation)
            let isLongGap = totalDuration > maxInterpolationGap

            for record in pendingRecords {
                let t = max(0, min(1, record.timestamp.timeIntervalSince(anchorTime) / totalDuration))

                let lat = anchorLocation.coordinate.latitude +
                    t * (newLocation.coordinate.latitude - anchorLocation.coordinate.latitude)
                let lon = anchorLocation.coordinate.longitude +
                    t * (newLocation.coordinate.longitude - anchorLocation.coordinate.longitude)

                // Long gaps get inflated accuracy to reflect greater uncertainty
                let estimatedAccuracy = max(
                    anchorLocation.horizontalAccuracy,
                    newLocation.horizontalAccuracy,
                    totalDistance * (isLongGap ? 0.5 : 0.1)
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

    /// Repair orphaned (0,0) records already in the database by interpolating
    /// between their nearest valid neighbors. Returns the number of records repaired.
    @discardableResult
    func repairOrphanedRecords() -> Int {
        let orphans = database.queryOrphaned()
        guard !orphans.isEmpty else { return 0 }

        // Get all valid records as anchors, sorted by timestamp
        let allRecords = database.queryAll()
        let anchors = allRecords
            .filter { $0.latitude != 0 || $0.longitude != 0 }
            .sorted { $0.timestamp < $1.timestamp }

        guard !anchors.isEmpty else { return 0 }

        var repaired = 0

        for orphan in orphans {
            let ts = orphan.timestamp

            // Find nearest anchor before and after
            let before = anchors.last { $0.timestamp <= ts }
            let after = anchors.first { $0.timestamp > ts }

            let lat: Double
            let lon: Double
            let accuracy: Double

            if let before = before, let after = after {
                // Interpolate between the two anchors
                let totalDuration = after.timestamp.timeIntervalSince(before.timestamp)
                guard totalDuration > 0 else {
                    // Same timestamp — use the before anchor
                    lat = before.latitude
                    lon = before.longitude
                    accuracy = before.locationAccuracy
                    database.update(
                        id: orphan.id,
                        latitude: lat, longitude: lon,
                        locationAccuracy: accuracy,
                        locationSource: LocationSource.interpolated.rawValue
                    )
                    repaired += 1
                    continue
                }

                let t = max(0, min(1, ts.timeIntervalSince(before.timestamp) / totalDuration))
                lat = before.latitude + t * (after.latitude - before.latitude)
                lon = before.longitude + t * (after.longitude - before.longitude)

                // Estimate distance between anchors for accuracy scaling
                let beforeLoc = CLLocation(latitude: before.latitude, longitude: before.longitude)
                let afterLoc = CLLocation(latitude: after.latitude, longitude: after.longitude)
                let dist = beforeLoc.distance(from: afterLoc)
                accuracy = max(before.locationAccuracy, after.locationAccuracy, dist * 0.5)
            } else if let nearest = before ?? after {
                // Only one side — snap to nearest anchor
                lat = nearest.latitude
                lon = nearest.longitude
                accuracy = nearest.locationAccuracy
            } else {
                continue
            }

            database.update(
                id: orphan.id,
                latitude: lat, longitude: lon,
                locationAccuracy: accuracy,
                locationSource: LocationSource.interpolated.rawValue
            )
            repaired += 1
        }

        return repaired
    }

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

        // Try transit first (snaps to train tracks); fall back to automobile
        request.transportType = .transit
        if let coords = await routeCoords(for: request) { return coords }

        request.transportType = .automobile
        return await routeCoords(for: request)
    }

    private func routeCoords(for request: MKDirections.Request) async -> [CLLocationCoordinate2D]? {
        guard let response = try? await MKDirections(request: request).calculate(),
              let route = response.routes.first else { return nil }
        let n = route.polyline.pointCount
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: n)
        route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: n))
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
