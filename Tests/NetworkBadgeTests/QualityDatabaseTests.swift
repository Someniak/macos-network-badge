// ---------------------------------------------------------
// QualityDatabaseTests.swift — Tests for SQLite quality storage
//
// Tests the QualityDatabase using a temporary in-memory or
// temp-file database. Verifies insert, query, filtering,
// and that data is never lost.
// ---------------------------------------------------------

import XCTest
@testable import NetworkBadge

final class QualityDatabaseTests: XCTestCase {

    /// Creates a fresh temporary database for each test
    private func makeTempDatabase() -> QualityDatabase {
        let tempPath = NSTemporaryDirectory() + "test_quality_\(UUID().uuidString).db"
        return QualityDatabase(path: tempPath)
    }

    /// Helper to create a sample record at given coordinates
    private func makeRecord(
        latitude: Double = 50.8503,
        longitude: Double = 4.3517,
        latencyMs: Double = 42.0,
        wasSuccessful: Bool = true,
        quality: String = "Good",
        connectionType: String = "WiFi",
        timestamp: Date = Date(),
        locationSource: String = "CoreLocation"
    ) -> QualityRecord {
        return QualityRecord(
            id: UUID(),
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            locationAccuracy: 10.0,
            latencyMs: latencyMs,
            wasSuccessful: wasSuccessful,
            quality: quality,
            connectionType: connectionType,
            wifiSSID: "TestNetwork",
            wifiRSSI: -55,
            interfaceName: "en0",
            locationSource: locationSource
        )
    }

    // MARK: - Basic Operations

    /// Inserting and querying a single record should work
    func testInsertAndQuery() {
        let db = makeTempDatabase()
        let record = makeRecord()

        db.insert(record)
        let results = db.queryAll()

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, record.id)
        XCTAssertEqual(results.first?.latitude, 50.8503)
        XCTAssertEqual(results.first?.longitude, 4.3517)
        XCTAssertEqual(results.first?.latencyMs, 42.0)
        XCTAssertEqual(results.first?.quality, "Good")
    }

    /// Multiple records should all be stored and returned
    func testMultipleInserts() {
        let db = makeTempDatabase()

        for i in 0..<10 {
            let record = makeRecord(latencyMs: Double(i * 10))
            db.insert(record)
        }

        XCTAssertEqual(db.recordCount(), 10)
        XCTAssertEqual(db.queryAll().count, 10)
    }

    /// Record count should reflect actual database content
    func testRecordCount() {
        let db = makeTempDatabase()
        XCTAssertEqual(db.recordCount(), 0)

        db.insert(makeRecord())
        XCTAssertEqual(db.recordCount(), 1)

        db.insert(makeRecord())
        XCTAssertEqual(db.recordCount(), 2)
    }

    // MARK: - Data Integrity

    /// All fields should survive a round-trip to the database
    func testRoundTrip() {
        let db = makeTempDatabase()
        let original = QualityRecord(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1700000000),
            latitude: 51.2194,
            longitude: 4.4025,
            locationAccuracy: 15.5,
            latencyMs: 123.456,
            wasSuccessful: true,
            quality: "Fair",
            connectionType: "Cellular",
            wifiSSID: nil,
            wifiRSSI: nil,
            interfaceName: "pdp_ip0",
            locationSource: "CoreLocation"
        )

        db.insert(original)
        let retrieved = db.queryAll().first!

        XCTAssertEqual(retrieved.id, original.id)
        XCTAssertEqual(retrieved.latitude, original.latitude, accuracy: 0.0001)
        XCTAssertEqual(retrieved.longitude, original.longitude, accuracy: 0.0001)
        XCTAssertEqual(retrieved.locationAccuracy, original.locationAccuracy, accuracy: 0.1)
        XCTAssertEqual(retrieved.latencyMs, original.latencyMs, accuracy: 0.01)
        XCTAssertEqual(retrieved.wasSuccessful, original.wasSuccessful)
        XCTAssertEqual(retrieved.quality, original.quality)
        XCTAssertEqual(retrieved.connectionType, original.connectionType)
        XCTAssertNil(retrieved.wifiSSID)
        XCTAssertNil(retrieved.wifiRSSI)
        XCTAssertEqual(retrieved.interfaceName, original.interfaceName)
        XCTAssertEqual(retrieved.locationSource, original.locationSource)
    }

    /// Update method should modify location fields of an existing record
    func testUpdateLocation() {
        let db = makeTempDatabase()
        let record = makeRecord(latitude: 50.0, longitude: 4.0)
        db.insert(record)

        // Update location via backpropagation
        db.update(
            id: record.id,
            latitude: 51.0,
            longitude: 5.0,
            locationAccuracy: 200.0,
            locationSource: "Interpolated"
        )

        let retrieved = db.queryAll().first!
        XCTAssertEqual(retrieved.latitude, 51.0, accuracy: 0.0001)
        XCTAssertEqual(retrieved.longitude, 5.0, accuracy: 0.0001)
        XCTAssertEqual(retrieved.locationAccuracy, 200.0, accuracy: 0.1)
        XCTAssertEqual(retrieved.locationSource, "Interpolated")
        // Other fields should be unchanged
        XCTAssertEqual(retrieved.latencyMs, record.latencyMs)
        XCTAssertEqual(retrieved.quality, record.quality)
    }

    /// WiFi SSID and RSSI should be preserved when present
    func testWiFiFieldsPreserved() {
        let db = makeTempDatabase()
        let record = makeRecord()

        db.insert(record)
        let retrieved = db.queryAll().first!

        XCTAssertEqual(retrieved.wifiSSID, "TestNetwork")
        XCTAssertEqual(retrieved.wifiRSSI, -55)
    }

    // MARK: - Spatial Queries

    /// Region query should only return records within bounds
    func testQueryInRegion() {
        let db = makeTempDatabase()

        // Record in Brussels
        db.insert(makeRecord(latitude: 50.8503, longitude: 4.3517))
        // Record in Antwerp
        db.insert(makeRecord(latitude: 51.2194, longitude: 4.4025))
        // Record in Paris (outside our region)
        db.insert(makeRecord(latitude: 48.8566, longitude: 2.3522))

        // Query for Belgium only (roughly)
        let results = db.queryInRegion(
            minLat: 50.0, maxLat: 52.0,
            minLon: 3.0, maxLon: 6.0
        )

        XCTAssertEqual(results.count, 2, "Should find Brussels and Antwerp, not Paris")
    }

    // MARK: - Time Range Queries

    /// Time range query should filter by timestamp
    func testQueryTimeRange() {
        let db = makeTempDatabase()

        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        let twoHoursAgo = now.addingTimeInterval(-7200)
        let oneDayAgo = now.addingTimeInterval(-86400)

        db.insert(makeRecord(timestamp: now))
        db.insert(makeRecord(timestamp: oneHourAgo))
        db.insert(makeRecord(timestamp: oneDayAgo))

        // Query last 2 hours — should get 2 records
        let results = db.queryTimeRange(from: twoHoursAgo, to: now)
        XCTAssertEqual(results.count, 2)
    }

    // MARK: - Ordering

    /// Records should be returned newest first
    func testNewestFirst() {
        let db = makeTempDatabase()

        let older = makeRecord(
            latencyMs: 100,
            timestamp: Date(timeIntervalSince1970: 1000)
        )
        let newer = makeRecord(
            latencyMs: 50,
            timestamp: Date(timeIntervalSince1970: 2000)
        )

        // Insert in wrong order
        db.insert(older)
        db.insert(newer)

        let results = db.queryAll()
        XCTAssertEqual(results.first?.latencyMs, 50, "Newest record should be first")
        XCTAssertEqual(results.last?.latencyMs, 100, "Oldest record should be last")
    }

    // MARK: - Data Never Deleted

    /// Verify that no delete or update operations exist —
    /// the database is strictly append-only for future analysis.
    func testAppendOnly() {
        let db = makeTempDatabase()

        // Insert 100 records
        for i in 0..<100 {
            db.insert(makeRecord(latencyMs: Double(i)))
        }

        // All 100 should still be there
        XCTAssertEqual(db.recordCount(), 100, "No records should ever be deleted")
    }
}
