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

    /// Whether location services are available and authorized
    @Published var isAuthorized: Bool = false

    /// Whether we're actively tracking location
    @Published var isTracking: Bool = false

    /// Number of records saved in the current session
    @Published var sessionRecordCount: Int = 0

    // MARK: - Dependencies

    /// The database to write quality records to
    private let database: QualityDatabase

    /// References to other monitors for reading current state
    private weak var networkMonitor: NetworkMonitor?
    private weak var latencyMonitor: LatencyMonitor?

    // MARK: - Private Properties

    private let locationManager = CLLocationManager()

    /// Minimum distance in meters before recording a new measurement
    private let minimumDistance: CLLocationDistance = 50.0

    /// Last location where we recorded a measurement
    private var lastRecordedLocation: CLLocation?

    /// Minimum time between recordings (prevents spam when jittering at one spot)
    private let minimumInterval: TimeInterval = 10.0

    /// Timestamp of last recording
    private var lastRecordedTime: Date?

    // MARK: - Initialization

    init(database: QualityDatabase) {
        self.database = database
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = minimumDistance
    }

    // MARK: - Start / Stop

    /// Begin tracking location. Must be called after setting monitor references.
    func start(networkMonitor: NetworkMonitor, latencyMonitor: LatencyMonitor) {
        self.networkMonitor = networkMonitor
        self.latencyMonitor = latencyMonitor

        // Request authorization (shows system prompt on first launch)
        locationManager.requestWhenInUseAuthorization()

        updateAuthorizationStatus()
    }

    /// Stop tracking location.
    func stop() {
        locationManager.stopUpdatingLocation()
        isTracking = false
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorizationStatus()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Update published coordinates
        DispatchQueue.main.async { [weak self] in
            self?.latitude = location.coordinate.latitude
            self?.longitude = location.coordinate.longitude
        }

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
        let status = locationManager.authorizationStatus

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch status {
            case .authorizedAlways, .authorized:
                self.isAuthorized = true
                if !self.isTracking {
                    self.locationManager.startUpdatingLocation()
                    self.isTracking = true
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
    private func recordIfNeeded(at location: CLLocation) {
        // Skip if location accuracy is too poor (e.g. > 200m)
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 200 else {
            return
        }

        // Check minimum distance from last recording
        if let lastLocation = lastRecordedLocation {
            let distance = location.distance(from: lastLocation)
            if distance < minimumDistance {
                return
            }
        }

        // Check minimum time interval
        if let lastTime = lastRecordedTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minimumInterval {
                return
            }
        }

        // We need current network data
        guard let network = networkMonitor, let latency = latencyMonitor else {
            return
        }

        // Don't record if there's no latency measurement yet
        guard latency.samples.count > 0 else {
            return
        }

        // Get the most recent sample
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
            interfaceName: network.interfaceName
        )

        // Write to database (off main thread is fine — SQLite handles concurrency)
        database.insert(record)

        // Update tracking state
        lastRecordedLocation = location
        lastRecordedTime = Date()

        DispatchQueue.main.async { [weak self] in
            self?.sessionRecordCount += 1
        }
    }
}
