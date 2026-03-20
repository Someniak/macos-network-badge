// ---------------------------------------------------------
// LocationMonitorTests.swift — Tests for GPS authorization handling
//
// These tests verify that LocationMonitor correctly responds to
// different CLAuthorizationStatus values via apply(authorizationStatus:).
// ---------------------------------------------------------

import XCTest
import CoreLocation
@testable import NetworkBadge

final class LocationMonitorTests: XCTestCase {

    // MARK: - Helpers

    private func makeMonitor() -> LocationMonitor {
        // Reset persisted tracking state to avoid test pollution
        UserDefaults.standard.removeObject(forKey: "gpsTrackingEnabled")
        let path = NSTemporaryDirectory() + "loc_test_\(UUID().uuidString).db"
        return LocationMonitor(database: QualityDatabase(path: path))
    }

    /// Wait for main-queue async work in apply(authorizationStatus:) to settle.
    private func waitForMainQueue(timeout: TimeInterval = 1.0) {
        let exp = expectation(description: "main queue flush")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: timeout)
    }

    // MARK: - Tests

    /// .authorized + tracking enabled → isAuthorized=true, isTracking=true
    func testAuthorizedWhenInUseStartsTracking() {
        let monitor = makeMonitor()
        monitor.isTrackingEnabled = true

        monitor.apply(authorizationStatus: .authorized)
        waitForMainQueue()

        XCTAssertTrue(monitor.isAuthorized)
        XCTAssertTrue(monitor.isTracking)
    }

    /// .authorizedAlways + tracking enabled → isAuthorized=true, isTracking=true
    func testAuthorizedAlwaysStartsTracking() {
        let monitor = makeMonitor()
        monitor.isTrackingEnabled = true

        monitor.apply(authorizationStatus: .authorizedAlways)
        waitForMainQueue()

        XCTAssertTrue(monitor.isAuthorized)
        XCTAssertTrue(monitor.isTracking)
    }

    /// .denied → isAuthorized=false, isTracking=false
    func testDeniedStopsTracking() {
        let monitor = makeMonitor()
        monitor.isTrackingEnabled = true

        monitor.apply(authorizationStatus: .denied)
        waitForMainQueue()

        XCTAssertFalse(monitor.isAuthorized)
        XCTAssertFalse(monitor.isTracking)
    }

    /// .notDetermined → isAuthorized=false, isTracking unchanged (false)
    func testNotDeterminedLeavesTrackingOff() {
        let monitor = makeMonitor()

        monitor.apply(authorizationStatus: .notDetermined)
        waitForMainQueue()

        XCTAssertFalse(monitor.isAuthorized)
        XCTAssertFalse(monitor.isTracking)
    }

    /// .authorized + tracking disabled → isAuthorized=true, isTracking=false
    func testAuthorizedButTrackingDisabledDoesNotStart() {
        let monitor = makeMonitor()
        // isTrackingEnabled defaults to false — do NOT set it to avoid triggering
        // requestWhenInUseAuthorization() which hits the real CLLocationManager.

        monitor.apply(authorizationStatus: .authorized)
        waitForMainQueue()

        XCTAssertTrue(monitor.isAuthorized)
        XCTAssertFalse(monitor.isTracking)
    }
}
