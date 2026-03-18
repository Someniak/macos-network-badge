// ---------------------------------------------------------
// QualityRecordTests.swift — Tests for QualityRecord model
//
// Verifies that quality records are created correctly from
// monitor state, and that quality levels are properly derived.
// ---------------------------------------------------------

import XCTest
@testable import NetworkBadge

final class QualityRecordTests: XCTestCase {

    // MARK: - Factory Method Tests

    /// Creating a record from monitor state should populate all fields
    func testFromMonitorState() {
        let record = QualityRecord.from(
            latitude: 50.8503,
            longitude: 4.3517,
            locationAccuracy: 10.0,
            latencyMs: 42.5,
            wasSuccessful: true,
            connectionType: .wifi,
            wifiSSID: "NMBS-WiFi",
            wifiRSSI: -55,
            interfaceName: "en0"
        )

        XCTAssertEqual(record.latitude, 50.8503)
        XCTAssertEqual(record.longitude, 4.3517)
        XCTAssertEqual(record.locationAccuracy, 10.0)
        XCTAssertEqual(record.latencyMs, 42.5)
        XCTAssertTrue(record.wasSuccessful)
        XCTAssertEqual(record.connectionType, "WiFi")
        XCTAssertEqual(record.wifiSSID, "NMBS-WiFi")
        XCTAssertEqual(record.wifiRSSI, -55)
        XCTAssertEqual(record.interfaceName, "en0")
    }

    /// Successful measurement should derive quality from latency
    func testQualityDerivedFromLatency() {
        let excellent = QualityRecord.from(
            latitude: 0, longitude: 0, locationAccuracy: 5,
            latencyMs: 20, wasSuccessful: true,
            connectionType: .wifi, wifiSSID: nil, wifiRSSI: nil,
            interfaceName: "en0"
        )
        XCTAssertEqual(excellent.quality, "Excellent")
        XCTAssertEqual(excellent.qualityLevel, .excellent)

        let poor = QualityRecord.from(
            latitude: 0, longitude: 0, locationAccuracy: 5,
            latencyMs: 200, wasSuccessful: true,
            connectionType: .wifi, wifiSSID: nil, wifiRSSI: nil,
            interfaceName: "en0"
        )
        XCTAssertEqual(poor.quality, "Poor")
        XCTAssertEqual(poor.qualityLevel, .poor)
    }

    /// Failed measurement should be marked as "Bad" quality
    func testFailedMeasurementIsBad() {
        let failed = QualityRecord.from(
            latitude: 0, longitude: 0, locationAccuracy: 5,
            latencyMs: 0, wasSuccessful: false,
            connectionType: .wifi, wifiSSID: nil, wifiRSSI: nil,
            interfaceName: "en0"
        )
        XCTAssertEqual(failed.quality, "Bad")
        XCTAssertEqual(failed.qualityLevel, .bad)
    }

    /// Each record should have a unique ID
    func testUniqueIDs() {
        let record1 = QualityRecord.from(
            latitude: 0, longitude: 0, locationAccuracy: 5,
            latencyMs: 42, wasSuccessful: true,
            connectionType: .wifi, wifiSSID: nil, wifiRSSI: nil,
            interfaceName: "en0"
        )
        let record2 = QualityRecord.from(
            latitude: 0, longitude: 0, locationAccuracy: 5,
            latencyMs: 42, wasSuccessful: true,
            connectionType: .wifi, wifiSSID: nil, wifiRSSI: nil,
            interfaceName: "en0"
        )
        XCTAssertNotEqual(record1.id, record2.id)
    }

    /// WiFi fields should be nil for non-WiFi connections
    func testNonWiFiConnection() {
        let record = QualityRecord.from(
            latitude: 0, longitude: 0, locationAccuracy: 5,
            latencyMs: 42, wasSuccessful: true,
            connectionType: .ethernet, wifiSSID: nil, wifiRSSI: nil,
            interfaceName: "en6"
        )
        XCTAssertNil(record.wifiSSID)
        XCTAssertNil(record.wifiRSSI)
        XCTAssertEqual(record.connectionType, "Ethernet")
    }

    /// Quality level should handle unknown quality strings gracefully
    func testUnknownQualityLevel() {
        let record = QualityRecord(
            id: UUID(),
            timestamp: Date(),
            latitude: 0, longitude: 0,
            locationAccuracy: 5,
            latencyMs: 0,
            wasSuccessful: false,
            quality: "SomeUnknownValue",
            connectionType: "WiFi",
            wifiSSID: nil,
            wifiRSSI: nil,
            interfaceName: "en0"
        )
        // Should fall back to .unknown when the string doesn't match
        XCTAssertEqual(record.qualityLevel, .unknown)
    }
}
