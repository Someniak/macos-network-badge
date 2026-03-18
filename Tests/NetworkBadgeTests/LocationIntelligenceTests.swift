// ---------------------------------------------------------
// LocationIntelligenceTests.swift — Tests for smart location processing
//
// Tests Kalman filtering, outlier detection, backpropagation,
// bearing calculation, speed estimation, and trail building.
// ---------------------------------------------------------

import XCTest
import CoreLocation
@testable import NetworkBadge

final class LocationIntelligenceTests: XCTestCase {

    // MARK: - Helpers

    private func makeIntelligence() -> (LocationIntelligence, QualityDatabase) {
        let path = NSTemporaryDirectory() + "li_test_\(UUID().uuidString).db"
        let db = QualityDatabase(path: path)
        let intelligence = LocationIntelligence(database: db)
        return (intelligence, db)
    }

    private func makeLocation(
        latitude: Double = 50.8503,
        longitude: Double = 4.3517,
        accuracy: Double = 10.0,
        timestamp: Date = Date()
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            timestamp: timestamp
        )
    }

    private func makeRecord(
        latitude: Double = 50.8503,
        longitude: Double = 4.3517,
        latencyMs: Double = 42.0,
        timestamp: Date = Date(),
        locationSource: String = "None"
    ) -> QualityRecord {
        QualityRecord(
            id: UUID(),
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            locationAccuracy: -1,
            latencyMs: latencyMs,
            wasSuccessful: true,
            quality: "Good",
            connectionType: "WiFi",
            wifiSSID: "Test",
            wifiRSSI: -55,
            interfaceName: "en0",
            locationSource: locationSource
        )
    }

    // MARK: - Kalman Filter Tests

    /// Kalman filter should reduce variance of noisy readings
    func testKalmanSmoothReducesNoise() {
        let (intelligence, _) = makeIntelligence()

        // Feed a series of noisy readings around a true position
        let trueLat = 50.8503
        let trueLon = 4.3517
        var outputLats: [Double] = []

        for i in 0..<10 {
            let noise = Double(i % 2 == 0 ? 1 : -1) * 0.005  // ~500m noise
            let location = makeLocation(
                latitude: trueLat + noise,
                longitude: trueLon,
                accuracy: 500.0,
                timestamp: Date().addingTimeInterval(Double(i) * 10)
            )
            let smoothed = intelligence.kalmanSmooth(location)
            outputLats.append(smoothed.coordinate.latitude)
        }

        // Output should have less spread than input (±0.005)
        let outputSpread = (outputLats.max()! - outputLats.min()!)
        XCTAssertLessThan(outputSpread, 0.01, "Kalman filter should reduce noise spread")
    }

    /// High-accuracy readings should be trusted more by the Kalman filter
    func testKalmanHighAccuracyTrusted() {
        let (intelligence, _) = makeIntelligence()

        // Initialize with a low-accuracy reading
        _ = intelligence.kalmanSmooth(makeLocation(latitude: 50.0, accuracy: 1000.0))

        // Feed a high-accuracy reading at a different position
        let highAccuracy = intelligence.kalmanSmooth(makeLocation(
            latitude: 51.0, accuracy: 5.0,
            timestamp: Date().addingTimeInterval(10)
        ))

        // Should move significantly toward the high-accuracy reading
        XCTAssertGreaterThan(highAccuracy.coordinate.latitude, 50.5,
            "High-accuracy reading should pull the estimate toward it")
    }

    /// Low-accuracy readings should barely move the Kalman estimate
    func testKalmanLowAccuracyDamped() {
        let (intelligence, _) = makeIntelligence()

        // Initialize with a high-accuracy reading
        _ = intelligence.kalmanSmooth(makeLocation(latitude: 50.0, accuracy: 5.0))

        // Feed a low-accuracy reading far away
        let lowAccuracy = intelligence.kalmanSmooth(makeLocation(
            latitude: 55.0, accuracy: 5000.0,
            timestamp: Date().addingTimeInterval(10)
        ))

        // Should barely move from 50.0
        XCTAssertLessThan(lowAccuracy.coordinate.latitude, 51.0,
            "Low-accuracy reading should barely move the estimate")
    }

    // MARK: - Accuracy Classification Tests

    /// Accuracy filter should classify locations correctly
    func testAccuracyFilter() {
        let (intelligence, _) = makeIntelligence()
        intelligence.accuracyThreshold = 2000.0

        let good = intelligence.shouldRecord(location: makeLocation(accuracy: 50.0))
        XCTAssertTrue(good.accept)
        XCTAssertEqual(good.source, .coreLocation)

        let low = intelligence.shouldRecord(location: makeLocation(accuracy: 500.0))
        XCTAssertTrue(low.accept)
        XCTAssertEqual(low.source, .lowAccuracy)

        let tooFar = intelligence.shouldRecord(location: makeLocation(accuracy: 3000.0))
        XCTAssertFalse(tooFar.accept)
        XCTAssertEqual(tooFar.source, .none)

        let negative = intelligence.shouldRecord(location: makeLocation(accuracy: -1.0))
        XCTAssertFalse(negative.accept)
    }

    // MARK: - Outlier Detection Tests

    /// Two locations 1000km apart in 1 second should be rejected
    func testOutlierDetection() {
        let (intelligence, _) = makeIntelligence()

        let now = Date()
        // First location: Brussels
        let brussels = makeLocation(latitude: 50.8503, longitude: 4.3517, timestamp: now)
        intelligence.recordAnchor(brussels)

        // Second location: Rome, 1 second later
        let rome = makeLocation(
            latitude: 41.9028, longitude: 12.4964,
            timestamp: now.addingTimeInterval(1)
        )
        let result = intelligence.validateLocation(rome)
        XCTAssertNil(result, "1000km in 1s should be rejected as outlier")
    }

    /// 300km/h over 1 hour should be accepted (train speed)
    func testOutlierAcceptsTrainSpeed() {
        let (intelligence, _) = makeIntelligence()

        let now = Date()
        // Brussels
        intelligence.recordAnchor(makeLocation(
            latitude: 50.8503, longitude: 4.3517, timestamp: now
        ))

        // Paris, 1.5 hours later (~300km, ~55 m/s)
        let paris = makeLocation(
            latitude: 48.8566, longitude: 2.3522,
            timestamp: now.addingTimeInterval(5400)
        )
        let result = intelligence.validateLocation(paris)
        XCTAssertNotNil(result, "Train speed should be accepted")
    }

    /// First location should always be accepted (no prior anchor)
    func testFirstLocationAlwaysAccepted() {
        let (intelligence, _) = makeIntelligence()
        let location = makeLocation()
        let result = intelligence.validateLocation(location)
        XCTAssertNotNil(result)
    }

    // MARK: - Backpropagation Tests

    /// Buffer 5 records, provide anchors, verify interpolated positions
    func testBackpropagation() {
        let (intelligence, db) = makeIntelligence()

        let baseTime = Date()

        // Set up start anchor: Brussels
        let startLocation = makeLocation(
            latitude: 50.8503, longitude: 4.3517, timestamp: baseTime
        )
        intelligence.recordAnchor(startLocation)

        // Buffer 5 records with no GPS, spaced 10s apart
        for i in 1...5 {
            let record = makeRecord(
                latitude: 0, longitude: 0,
                timestamp: baseTime.addingTimeInterval(Double(i) * 10)
            )
            db.insert(record)
            intelligence.bufferRecord(record)
        }

        XCTAssertEqual(intelligence.pendingCount, 5)

        // New GPS fix arrives: Antwerp (60s later)
        let endLocation = makeLocation(
            latitude: 51.2194, longitude: 4.4025,
            timestamp: baseTime.addingTimeInterval(60)
        )
        intelligence.backpropagate(newLocation: endLocation)

        XCTAssertEqual(intelligence.pendingCount, 0, "Pending records should be flushed")

        // Verify records were updated in the database
        let records = db.queryAll()
        for record in records {
            if record.locationSource == LocationSource.interpolated.rawValue {
                // Interpolated lat should be between Brussels and Antwerp
                XCTAssertGreaterThan(record.latitude, 50.8, "Interpolated lat should be north of Brussels")
                XCTAssertLessThan(record.latitude, 51.3, "Interpolated lat should be south of Antwerp+")
            }
        }
    }

    /// Gap > maxInterpolationGap should discard pending records
    func testBackpropagationGapTooLarge() {
        let (intelligence, db) = makeIntelligence()
        intelligence.maxInterpolationGap = 60  // 1 minute max

        let baseTime = Date().addingTimeInterval(-600)  // 10 minutes ago

        intelligence.recordAnchor(makeLocation(timestamp: baseTime))

        let record = makeRecord(timestamp: baseTime.addingTimeInterval(30))
        db.insert(record)
        intelligence.bufferRecord(record)

        // New fix arrives 10 minutes later (gap > 60s)
        let lateLocation = makeLocation(
            latitude: 51.0, longitude: 4.5,
            timestamp: Date()
        )
        intelligence.backpropagate(newLocation: lateLocation)

        XCTAssertEqual(intelligence.pendingCount, 0, "Pending should be discarded on large gap")
    }

    // MARK: - Bearing Tests

    /// Moving due east should give bearing ~90°
    func testBearingCalculation() {
        let (intelligence, _) = makeIntelligence()

        let start = makeLocation(latitude: 50.0, longitude: 4.0)
        let east = makeLocation(latitude: 50.0, longitude: 5.0)

        intelligence.updateBearing(from: start, to: east)

        XCTAssertGreaterThan(intelligence.currentBearing, 80)
        XCTAssertLessThan(intelligence.currentBearing, 100)
    }

    /// Moving due north should give bearing ~0°
    func testBearingNorth() {
        let (intelligence, _) = makeIntelligence()

        let start = makeLocation(latitude: 50.0, longitude: 4.0)
        let north = makeLocation(latitude: 51.0, longitude: 4.0)

        intelligence.updateBearing(from: start, to: north)

        XCTAssertLessThan(intelligence.currentBearing, 10)
    }

    // MARK: - Speed Estimation Tests

    /// Feed 5 locations, verify estimated speed is reasonable
    func testSpeedEstimation() {
        let (intelligence, _) = makeIntelligence()

        let baseTime = Date()
        // ~111km between each degree of latitude, 10s apart
        for i in 0..<5 {
            let location = makeLocation(
                latitude: 50.0 + Double(i) * 0.001,  // ~111m per step
                timestamp: baseTime.addingTimeInterval(Double(i) * 10)
            )
            intelligence.recordAnchor(location)
        }

        // 4 steps of ~111m in 40 seconds ≈ ~11 m/s
        let speed = intelligence.estimatedSpeed
        XCTAssertGreaterThan(speed, 5, "Should detect movement")
        XCTAssertLessThan(speed, 20, "Speed should be reasonable")
    }

    // MARK: - Buffer Tests

    /// Buffer should be capped at 50 entries
    func testPendingBufferCap() {
        let (intelligence, _) = makeIntelligence()

        for _ in 0..<60 {
            intelligence.bufferRecord(makeRecord())
        }

        XCTAssertEqual(intelligence.pendingCount, 50, "Buffer should be capped at 50")
    }

    /// flushOnStop should clear all pending records
    func testFlushOnStop() {
        let (intelligence, _) = makeIntelligence()

        for _ in 0..<10 {
            intelligence.bufferRecord(makeRecord())
        }

        intelligence.flushOnStop()
        XCTAssertEqual(intelligence.pendingCount, 0)
    }

    // MARK: - Trail Building Tests

    /// 3 records should produce 2 trail segments
    func testTrailSegmentBuilder() {
        let baseTime = Date()
        let records = [
            makeRecord(latitude: 50.0, longitude: 4.0, timestamp: baseTime, locationSource: "CoreLocation"),
            makeRecord(latitude: 50.1, longitude: 4.1, timestamp: baseTime.addingTimeInterval(30), locationSource: "CoreLocation"),
            makeRecord(latitude: 50.2, longitude: 4.2, timestamp: baseTime.addingTimeInterval(60), locationSource: "CoreLocation"),
        ]

        let segments = QualityTrailBuilder.buildTrail(from: records)
        XCTAssertEqual(segments.count, 2)
    }

    /// 10-minute gap between records should split the trail
    func testTrailSkipsLargeGaps() {
        let baseTime = Date()
        let records = [
            makeRecord(latitude: 50.0, longitude: 4.0, timestamp: baseTime, locationSource: "CoreLocation"),
            makeRecord(latitude: 50.1, longitude: 4.1, timestamp: baseTime.addingTimeInterval(30), locationSource: "CoreLocation"),
            // 15-minute gap
            makeRecord(latitude: 50.2, longitude: 4.2, timestamp: baseTime.addingTimeInterval(930), locationSource: "CoreLocation"),
        ]

        let segments = QualityTrailBuilder.buildTrail(from: records)
        XCTAssertEqual(segments.count, 1, "Should only have 1 segment (gap breaks the trail)")
    }

    /// Records with lat=0, lon=0 should be skipped in trail
    func testTrailSkipsNoLocationRecords() {
        let baseTime = Date()
        let records = [
            makeRecord(latitude: 50.0, longitude: 4.0, timestamp: baseTime, locationSource: "CoreLocation"),
            makeRecord(latitude: 0, longitude: 0, timestamp: baseTime.addingTimeInterval(10), locationSource: "None"),
            makeRecord(latitude: 50.1, longitude: 4.1, timestamp: baseTime.addingTimeInterval(20), locationSource: "CoreLocation"),
        ]

        let segments = QualityTrailBuilder.buildTrail(from: records)
        XCTAssertEqual(segments.count, 1, "Should skip the no-location record")
    }
}
