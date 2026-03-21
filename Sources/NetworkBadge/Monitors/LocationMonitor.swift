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
final class LocationMonitor: NSObject, ObservableObject, CLLocationManagerDelegate, @unchecked Sendable {

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
                #if os(macOS)
                if gps2ip.isEnabled { gps2ip.start() }
                #endif
                locationManager.requestWhenInUseAuthorization()
                updateAuthorizationStatus()
            } else {
                locationManager.stopUpdatingLocation()
                cancelStationaryTimer()
                #if os(macOS)
                gps2ip.stop()
                #endif
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
    @Published var minimumDistance: CLLocationDistance = 20.0 {
        didSet {
            UserDefaults.standard.set(minimumDistance, forKey: "gpsMinimumDistance")
            locationManager.distanceFilter = minimumDistance
        }
    }

    /// Last location where we recorded a measurement
    private var lastRecordedLocation: CLLocation?

    /// Minimum time between recordings (prevents spam when jittering at one spot)
    @Published var minimumInterval: TimeInterval = 3.0 {
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

    /// Dead reckoning: last real GPS fix and when it arrived
    private var lastRealGPSLocation: CLLocation?
    private var lastRealGPSTime: Date?
    private var deadReckoningTimer: Timer?

    /// Maximum stationary poll interval (5 minutes) to prevent unbounded growth
    private let maxStationaryInterval: TimeInterval = 300

    /// Guards against didSet side-effects during init
    private var isInitializing = true

    #if os(macOS)
    /// GPS2IP iPhone GPS source (macOS only — iOS has native GPS)
    var gps2ip = GPS2IPSource()
    #endif

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(database: QualityDatabase) {
        self.database = database
        self.intelligence = LocationIntelligence(database: database)
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        #if os(iOS)
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
        #endif
        // Load persisted value. didSet is safe here because isInitializing
        // prevents it from starting location services before start() is called.
        if UserDefaults.standard.object(forKey: "gpsTrackingEnabled") != nil {
            isTrackingEnabled = UserDefaults.standard.bool(forKey: "gpsTrackingEnabled")
        }
        // Migrate to lower defaults (v2). If the saved value exactly matches the old
        // default it was never customised — reset to the new lower value.
        let savedDistance = UserDefaults.standard.double(forKey: "gpsMinimumDistance")
        if savedDistance > 0 && savedDistance != 50.0 { minimumDistance = savedDistance }
        let savedInterval = UserDefaults.standard.double(forKey: "gpsMinimumInterval")
        if savedInterval > 0 && savedInterval != 10.0 { minimumInterval = savedInterval }
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

        #if os(macOS)
        gps2ip.onLocation = { [weak self] location in
            DispatchQueue.main.async {
                guard let self, self.isTracking else { return }
                self.latitude = location.coordinate.latitude
                self.longitude = location.coordinate.longitude
                self.currentLocation = location
                self.lastRealGPSLocation = location
                self.lastRealGPSTime = Date()
                // GPS2IP is real iPhone GPS — skip Kalman/outlier/accuracy pipeline
                self.recordGPS2IP(at: location)
            }
        }

        gps2ip.$isEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled && self.isTracking { self.gps2ip.start() }
                else { self.gps2ip.stop() }
            }
            .store(in: &cancellables)
        #endif

        guard isTrackingEnabled else { return }

        #if os(macOS)
        if gps2ip.isEnabled { gps2ip.start() }
        #endif

        // Request authorization (shows system prompt on first launch)
        locationManager.requestWhenInUseAuthorization()

        updateAuthorizationStatus()
    }

    /// Stop tracking location.
    func stop() {
        locationManager.stopUpdatingLocation()
        cancelStationaryTimer()
        stopDeadReckoning()
        #if os(macOS)
        gps2ip.stop()
        #endif
        intelligence.flushOnStop()
        intelligence.resetKalman()
        currentLocation = nil
        lastRealGPSLocation = nil
        lastRealGPSTime = nil
        latitude = nil
        longitude = nil
        isTracking = false
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorizationStatus()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isTracking else { return }
            #if os(macOS)
            // When GPS2IP is actively providing fixes, it gives far better
            // results than CoreLocation's Wi-Fi positioning. Skip CL updates
            // to avoid spider-web patterns from dual-source recording.
            // Falls back to CoreLocation if GPS2IP goes stale (>15s without fix).
            guard !self.gps2ip.isActivelyFixing else { return }
            #endif
            self.latitude = location.coordinate.latitude
            self.longitude = location.coordinate.longitude
            self.currentLocation = location
            self.lastRealGPSLocation = location
            self.lastRealGPSTime = Date()
            self.recordIfNeeded(at: location)
        }
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
                // CoreWLAN's ssid() requires location authorization on macOS 14+.
                // NWPathMonitor often fires before authorization is granted, so
                // the initial SSID read returns nil. Re-read now that we're authorized.
                self.networkMonitor?.refreshWiFiInfo()
                if !self.isTracking && self.isTrackingEnabled {
                    self.locationManager.startUpdatingLocation()
                    self.isTracking = true
                    self.currentStationaryInterval = self.minimumInterval
                    self.scheduleStationaryPoll()
                    self.startDeadReckoning()
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

        let speed = intelligence.currentSpeedKmh
        let ml = mlFields(location: validLocation)
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
            locationSource: source,
            speedKmh: speed > 1 ? speed : nil,
            altitude: ml.altitude,
            jitter: ml.jitter,
            packetLossRatio: ml.packetLossRatio,
            courseChangeRate: ml.courseChangeRate
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

    #if os(macOS)
    /// Records a GPS2IP location directly, skipping the Kalman / outlier / accuracy
    /// pipeline. iPhone GPS is already smooth and accurate; running it through the
    /// Wi-Fi-noise-oriented intelligence layer only drops good fixes.
    private func recordGPS2IP(at location: CLLocation) {
        // Distance gate
        if let last = lastRecordedLocation, location.distance(from: last) < minimumDistance { return }
        // Time gate
        if let last = lastRecordedTime, Date().timeIntervalSince(last) < minimumInterval { return }

        guard let network = networkMonitor, let latency = latencyMonitor else { return }
        guard latency.samples.count > 0 else { return }

        let latestSample = latency.samples.first
        let speed = intelligence.currentSpeedKmh
        let ml = mlFields(location: location)
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
            locationSource: .gps2ip,
            speedKmh: speed > 1 ? speed : nil,
            altitude: ml.altitude,
            jitter: ml.jitter,
            packetLossRatio: ml.packetLossRatio,
            courseChangeRate: ml.courseChangeRate
        )
        database.insert(record)
        intelligence.recordAnchor(location)
        intelligence.backpropagate(newLocation: location)

        lastRecordedLocation = location
        lastRecordedTime = Date()

        sessionRecordCount += 1
        currentStationaryInterval = minimumInterval
        scheduleStationaryPoll()
    }
    #endif

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

        let ml = mlFields(location: nil)
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
            locationSource: .none,
            altitude: nil,
            jitter: ml.jitter,
            packetLossRatio: ml.packetLossRatio,
            courseChangeRate: ml.courseChangeRate
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

        let ml = mlFields(location: nil)
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
            locationSource: .ipGeolocation,
            altitude: nil,
            jitter: ml.jitter,
            packetLossRatio: ml.packetLossRatio,
            courseChangeRate: ml.courseChangeRate
        )

        database.insert(record)

        DispatchQueue.main.async { [weak self] in
            self?.sessionRecordCount += 1
        }
    }

    // MARK: - ML Feature Helpers

    /// Collects ML feature fields from current monitor state and a location.
    private func mlFields(location: CLLocation?) -> (altitude: Double?, jitter: Double?, packetLossRatio: Double?, courseChangeRate: Double?) {
        let altitude = location.flatMap { $0.verticalAccuracy >= 0 ? $0.altitude : nil }
        return (
            altitude: altitude,
            jitter: latencyMonitor?.jitter,
            packetLossRatio: latencyMonitor?.packetLossRatio,
            courseChangeRate: intelligence.courseChangeRate
        )
    }

    // MARK: - Dead Reckoning

    private func startDeadReckoning() {
        deadReckoningTimer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tickDeadReckoning()
        }
        RunLoop.main.add(t, forMode: .common)
        deadReckoningTimer = t
    }

    private func stopDeadReckoning() {
        deadReckoningTimer?.invalidate()
        deadReckoningTimer = nil
    }

    /// Project position forward between GPS fixes using bearing + estimated speed.
    private func tickDeadReckoning() {
        guard isTracking,
              let base = lastRealGPSLocation,
              let baseTime = lastRealGPSTime else { return }

        let elapsed = Date().timeIntervalSince(baseTime)
        let speedMs = intelligence.estimatedSpeed

        // Only dead reckon when GPS is stale (>3 s) and we're actually moving
        guard elapsed > 3, speedMs > 0.5 else { return }

        let bearing = intelligence.currentBearing
        let distance = speedMs * elapsed
        let projected = CoordinateUtils.projectCoordinate(from: base.coordinate, distance: distance, bearing: bearing)
        latitude = projected.latitude
        longitude = projected.longitude
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

        #if os(macOS)
        // When GPS2IP is actively providing fixes, don't create CoreLocation-sourced
        // records — GPS2IP's own recordGPS2IP() handles recording with better accuracy.
        // Falls back to CoreLocation if GPS2IP goes stale (>15s without fix).
        guard !gps2ip.isActivelyFixing else {
            scheduleStationaryPoll()
            return
        }
        #endif

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
        let speed = intelligence.currentSpeedKmh
        let ml = mlFields(location: location)
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
            locationSource: source,
            speedKmh: speed > 1 ? speed : nil,
            altitude: ml.altitude,
            jitter: ml.jitter,
            packetLossRatio: ml.packetLossRatio,
            courseChangeRate: ml.courseChangeRate
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
