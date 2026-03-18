// ---------------------------------------------------------
// LocationMonitor.swift — GPS location tracking for quality mapping
//
// Monitors the user's location using CoreLocation and triggers
// network quality recordings when the user moves significantly.
// Designed for travel scenarios (trains, cafés, etc.).
//
// Uses "significant location change" mode for battery efficiency —
// records only when the user moves roughly 50+ meters.
// ---------------------------------------------------------

import Combine
import CoreLocation
import Foundation

/// Monitors GPS location and records quality measurements on location change.
///
/// Usage:
///   let monitor = LocationMonitor(database: db)
///   monitor.start(networkMonitor: network, latencyMonitor: latency)
///
final class LocationMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Published Properties

    /// Current latitude (nil if no location yet)
    @Published var latitude: Double?

    /// Current longitude (nil if no location yet)
    @Published var longitude: Double?

    /// Whether the user has enabled GPS tracking (persisted; defaults to false)
    @Published var isTrackingEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isTrackingEnabled, forKey: "gpsTrackingEnabled")
            guard !isInitializing else { return }
            if isTrackingEnabled {
                locationManager.requestWhenInUseAuthorization()
                updateAuthorizationStatus()
            } else {
                locationManager.stopUpdatingLocation()
                cancelStationaryTimer()
                isTracking = false
            }
        }
    }

    /// Whether location services are available and authorized
    @Published var isAuthorized: Bool = false

    /// Whether we're actively tracking location
    @Published var isTracking: Bool = false

    /// Number of records saved in the current session
    @Published var sessionRecordCount: Int = 0

    // MARK: - Dependencies

    /// The database to write quality records to
    private let database: QualityDatabase

    /// Smart location processing (Kalman filter, backpropagation, outlier detection)
    var intelligence: LocationIntelligence

    /// References to other monitors for reading current state
    private weak var networkMonitor: NetworkMonitor?
    private weak var latencyMonitor: LatencyMonitor?

    // MARK: - Private Properties

    private let locationManager = CLLocationManager()

    /// Minimum distance in meters before recording a new measurement
    @Published var minimumDistance: CLLocationDistance = 50.0 {
        didSet {
            UserDefaults.standard.set(minimumDistance, forKey: "gpsMinimumDistance")
            locationManager.distanceFilter = minimumDistance
        }
    }

    /// Last location where we recorded a measurement
    private var lastRecordedLocation: CLLocation?

    /// Minimum time between recordings (prevents spam when jittering at one spot)
    @Published var minimumInterval: TimeInterval = 10.0 {
        didSet {
            UserDefaults.standard.set(minimumInterval, forKey: "gpsMinimumInterval")
        }
    }

    /// Timestamp of last recording
    private var lastRecordedTime: Date?

    /// Backoff multiplier applied to the stationary poll interval after each record.
    /// e.g. 2.0 means: 10s → 20s → 40s → 80s …
    @Published var stationaryMultiplier: Double = 2.0 {
        didSet { UserDefaults.standard.set(stationaryMultiplier, forKey: "gpsStationaryMultiplier") }
    }

    private var currentLocation: CLLocation?
    private var stationaryTimer: Timer?
    private var currentStationaryInterval: TimeInterval = 10

    /// Maximum stationary poll interval (5 minutes) to prevent unbounded growth
    private let maxStationaryInterval: TimeInterval = 300

    /// Guards against didSet side-effects during init
    private var isInitializing = true

    // MARK: - Initialization

    init(database: QualityDatabase) {
        self.database = database
        self.intelligence = LocationIntelligence(database: database)
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        // Load persisted value. didSet is safe here because isInitializing
        // prevents it from starting location services before start() is called.
        if UserDefaults.standard.object(forKey: "gpsTrackingEnabled") != nil {
            isTrackingEnabled = UserDefaults.standard.bool(forKey: "gpsTrackingEnabled")
        }
        let savedDistance = UserDefaults.standard.double(forKey: "gpsMinimumDistance")
        if savedDistance > 0 { minimumDistance = savedDistance }
        let savedInterval = UserDefaults.standard.double(forKey: "gpsMinimumInterval")
        if savedInterval > 0 { minimumInterval = savedInterval }
        let savedMultiplier = UserDefaults.standard.double(forKey: "gpsStationaryMultiplier")
        if savedMultiplier > 0 { stationaryMultiplier = savedMultiplier }
        locationManager.distanceFilter = minimumDistance
        isInitializing = false
    }

    // MARK: - Start / Stop

    /// Begin tracking location. Must be called after setting monitor references.
    func start(networkMonitor: NetworkMonitor, latencyMonitor: LatencyMonitor) {
        self.networkMonitor = networkMonitor
        self.latencyMonitor = latencyMonitor

        guard isTrackingEnabled else { return }

        // Request authorization (shows system prompt on first launch)
        locationManager.requestWhenInUseAuthorization()

        updateAuthorizationStatus()
    }

    /// Stop tracking location.
    func stop() {
        locationManager.stopUpdatingLocation()
        cancelStationaryTimer()
        intelligence.flushOnStop()
        intelligence.resetKalman()
        currentLocation = nil
        latitude = nil
        longitude = nil
        isTracking = false
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorizationStatus()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isTracking, let location = locations.last else { return }

        // Update published coordinates
        DispatchQueue.main.async { [weak self] in
            self?.latitude = location.coordinate.latitude
            self?.longitude = location.coordinate.longitude
        }

        // Store current location for stationary polling
        currentLocation = location

        // Check if we should record a measurement
        recordIfNeeded(at: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // CLError.locationUnknown is temporary — the system will keep trying
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }
        print("[LocationMonitor] Location error: \(error.localizedDescription)")
    }

    // MARK: - Private Methods

    private func updateAuthorizationStatus() {
        apply(authorizationStatus: locationManager.authorizationStatus)
    }

    func apply(authorizationStatus status: CLAuthorizationStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            switch status {
            case .authorizedAlways, .authorized, .authorizedWhenInUse:
                self.isAuthorized = true
                if !self.isTracking && self.isTrackingEnabled {
                    self.locationManager.startUpdatingLocation()
                    self.isTracking = true
                    self.currentStationaryInterval = self.minimumInterval
                    self.scheduleStationaryPoll()
                }
            case .notDetermined:
                self.isAuthorized = false
            case .denied, .restricted:
                self.isAuthorized = false
                self.isTracking = false
            @unknown default:
                self.isAuthorized = false
            }
        }
    }

    /// Records a quality measurement if the user has moved enough.
    /// Uses LocationIntelligence for Kalman smoothing, outlier detection,
    /// and backpropagation when GPS is unavailable.
    private func recordIfNeeded(at rawLocation: CLLocation) {
        // 1. Kalman smooth the raw reading
        let location = intelligence.kalmanSmooth(rawLocation)

        // 2. Outlier detection — reject teleportation
        guard let validLocation = intelligence.validateLocation(location) else {
            return
        }

        // 3. Check accuracy — classify source
        let (accept, source) = intelligence.shouldRecord(location: validLocation)

        if !accept {
            // Location too inaccurate — buffer for backpropagation and try IP fallback
            bufferLatencyOnlyRecord()
            if intelligence.ipGeolocationEnabled {
                Task { [weak self] in await self?.recordWithIPFallback() }
            }
            return
        }

        // 4. Check minimum distance from last recording
        if let lastLocation = lastRecordedLocation {
            let distance = validLocation.distance(from: lastLocation)
            if distance < minimumDistance {
                return
            }
        }

        // 5. Check minimum time interval
        if let lastTime = lastRecordedTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minimumInterval {
                return
            }
        }

        // 6. We need current network data
        guard let network = networkMonitor, let latency = latencyMonitor else {
            return
        }

        // Don't record if there's no latency measurement yet
        guard latency.samples.count > 0 else {
            return
        }

        let latestSample = latency.samples.first

        let record = QualityRecord.from(
            latitude: validLocation.coordinate.latitude,
            longitude: validLocation.coordinate.longitude,
            locationAccuracy: validLocation.horizontalAccuracy,
            latencyMs: latestSample?.latencyMs ?? 0,
            wasSuccessful: latestSample?.wasSuccessful ?? false,
            connectionType: network.connectionType,
            wifiSSID: network.wifiSSID,
            wifiRSSI: network.wifiRSSI,
            interfaceName: network.interfaceName,
            locationSource: source
        )

        // Write to database
        database.insert(record)

        // Backpropagate any pending records now that we have a GPS fix
        intelligence.backpropagate(newLocation: validLocation)
        intelligence.recordAnchor(validLocation)

        // Update tracking state
        lastRecordedLocation = validLocation
        lastRecordedTime = Date()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sessionRecordCount += 1
            self.currentStationaryInterval = self.minimumInterval
            self.scheduleStationaryPoll()
        }
    }

    /// Buffer a latency-only record with no location (for later backpropagation).
    private func bufferLatencyOnlyRecord() {
        guard let network = networkMonitor, let latency = latencyMonitor else { return }
        guard latency.samples.count > 0 else { return }

        // Check minimum time interval to avoid spamming
        if let lastTime = lastRecordedTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minimumInterval { return }
        }

        let latestSample = latency.samples.first

        let record = QualityRecord.from(
            latitude: 0,
            longitude: 0,
            locationAccuracy: -1,
            latencyMs: latestSample?.latencyMs ?? 0,
            wasSuccessful: latestSample?.wasSuccessful ?? false,
            connectionType: network.connectionType,
            wifiSSID: network.wifiSSID,
            wifiRSSI: network.wifiRSSI,
            interfaceName: network.interfaceName,
            locationSource: .none
        )

        database.insert(record)
        intelligence.bufferRecord(record)
        lastRecordedTime = Date()

        DispatchQueue.main.async { [weak self] in
            self?.sessionRecordCount += 1
        }
    }

    /// Try IP geolocation as a fallback when CoreLocation fails.
    private func recordWithIPFallback() async {
        guard let coords = await intelligence.fetchIPGeolocation() else { return }
        guard let network = networkMonitor, let latency = latencyMonitor else { return }
        guard latency.samples.count > 0 else { return }

        let latestSample = latency.samples.first

        let record = QualityRecord.from(
            latitude: coords.latitude,
            longitude: coords.longitude,
            locationAccuracy: 50000,  // ~50km city-level accuracy
            latencyMs: latestSample?.latencyMs ?? 0,
            wasSuccessful: latestSample?.wasSuccessful ?? false,
            connectionType: network.connectionType,
            wifiSSID: network.wifiSSID,
            wifiRSSI: network.wifiRSSI,
            interfaceName: network.interfaceName,
            locationSource: .ipGeolocation
        )

        database.insert(record)

        DispatchQueue.main.async { [weak self] in
            self?.sessionRecordCount += 1
        }
    }

    private func scheduleStationaryPoll() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stationaryTimer?.invalidate()
            let t = Timer(timeInterval: self.currentStationaryInterval, repeats: false) {
                [weak self] _ in self?.performStationaryRecord()
            }
            RunLoop.main.add(t, forMode: .common)
            self.stationaryTimer = t
        }
    }

    private func cancelStationaryTimer() {
        stationaryTimer?.invalidate()
        stationaryTimer = nil
    }

    private func performStationaryRecord() {
        guard isTracking, let rawLocation = currentLocation else { return }

        let location = intelligence.kalmanSmooth(rawLocation)
        let (accept, source) = intelligence.shouldRecord(location: location)

        guard accept else {
            // Stationary but bad accuracy — buffer for backpropagation
            bufferLatencyOnlyRecord()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.currentStationaryInterval = min(
                    self.currentStationaryInterval * self.stationaryMultiplier,
                    self.maxStationaryInterval
                )
                self.scheduleStationaryPoll()
            }
            return
        }

        guard let network = networkMonitor, let latency = latencyMonitor else { return }
        guard latency.samples.count > 0 else { return }

        let latestSample = latency.samples.first
        let record = QualityRecord.from(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            locationAccuracy: location.horizontalAccuracy,
            latencyMs: latestSample?.latencyMs ?? 0,
            wasSuccessful: latestSample?.wasSuccessful ?? false,
            connectionType: network.connectionType,
            wifiSSID: network.wifiSSID,
            wifiRSSI: network.wifiRSSI,
            interfaceName: network.interfaceName,
            locationSource: source
        )
        database.insert(record)
        intelligence.recordAnchor(location)
        lastRecordedLocation = location
        lastRecordedTime = Date()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sessionRecordCount += 1
            self.currentStationaryInterval = min(
                self.currentStationaryInterval * self.stationaryMultiplier,
                self.maxStationaryInterval
            )
            self.scheduleStationaryPoll()
        }
    }
}
