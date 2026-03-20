// ---------------------------------------------------------
// QualityDatabase.swift — SQLite storage for quality records
//
// Stores GPS-tagged network quality measurements in a SQLite
// database under ~/.networkbadge/quality.db. Data is NEVER
// deleted — this is an append-only store designed for future
// predictive analysis.
//
// Uses raw SQLite C API (available on macOS without deps).
// ---------------------------------------------------------

import Foundation
import SQLite3

/// Persistent, append-only SQLite database for network quality records.
///
/// Usage:
///   let db = QualityDatabase()
///   db.insert(record)
///   let records = db.queryAll()
///
final class QualityDatabase {

    /// Path to the database file
    let databasePath: String

    /// SQLite connection handle
    private var db: OpaquePointer?

    // MARK: - Initialization

    /// Creates or opens the quality database.
    /// Default location: ~/.networkbadge/quality.db
    init(path: String? = nil) {
        if let path = path {
            self.databasePath = path
        } else {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let dir = "\(homeDir)/.networkbadge"
            // Create the hidden directory if it doesn't exist
            try? FileManager.default.createDirectory(
                atPath: dir,
                withIntermediateDirectories: true,
                attributes: nil
            )
            self.databasePath = "\(dir)/quality.db"
        }

        openDatabase()
        createTableIfNeeded()
        createIndicesIfNeeded()
        migrateSchemaIfNeeded()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private func openDatabase() {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databasePath, &db, flags, nil)
        if result != SQLITE_OK {
            print("[QualityDatabase] Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
        }

        // Enable WAL mode for better concurrent read/write performance
        execute("PRAGMA journal_mode=WAL")
        // Sync less often for better write performance (data is append-only, so safe)
        execute("PRAGMA synchronous=NORMAL")
    }

    private func createTableIfNeeded() {
        let sql = """
            CREATE TABLE IF NOT EXISTS quality_records (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                location_accuracy REAL NOT NULL,
                latency_ms REAL NOT NULL,
                was_successful INTEGER NOT NULL,
                quality TEXT NOT NULL,
                connection_type TEXT NOT NULL,
                wifi_ssid TEXT,
                wifi_rssi INTEGER,
                interface_name TEXT NOT NULL
            )
            """
        execute(sql)
    }

    private func createIndicesIfNeeded() {
        // Index on timestamp for time-range queries (predictive analysis)
        execute("""
            CREATE INDEX IF NOT EXISTS idx_quality_timestamp
            ON quality_records(timestamp)
            """)

        // Spatial index approximation for map queries
        // (real R-tree would be better, but this works for moderate data sizes)
        execute("""
            CREATE INDEX IF NOT EXISTS idx_quality_location
            ON quality_records(latitude, longitude)
            """)

        // Index on quality for filtering bad areas
        execute("""
            CREATE INDEX IF NOT EXISTS idx_quality_level
            ON quality_records(quality)
            """)
    }

    private func migrateSchemaIfNeeded() {
        // Add location_source column if it doesn't exist.
        // ALTER TABLE will error if column already exists — execute() logs and ignores.
        execute("ALTER TABLE quality_records ADD COLUMN location_source TEXT NOT NULL DEFAULT 'CoreLocation'")

        // Add speed_kmh column if it doesn't exist.
        execute("ALTER TABLE quality_records ADD COLUMN speed_kmh REAL")

        // ML feature columns
        execute("ALTER TABLE quality_records ADD COLUMN altitude REAL")
        execute("ALTER TABLE quality_records ADD COLUMN jitter REAL")
        execute("ALTER TABLE quality_records ADD COLUMN packet_loss_ratio REAL")
        execute("ALTER TABLE quality_records ADD COLUMN course_change_rate REAL")
    }

    // MARK: - Insert

    /// Inserts a quality record into the database. Never fails silently.
    func insert(_ record: QualityRecord) {
        let sql = """
            INSERT INTO quality_records (
                id, timestamp, latitude, longitude, location_accuracy,
                latency_ms, was_successful, quality, connection_type,
                wifi_ssid, wifi_rssi, interface_name, location_source,
                speed_kmh, altitude, jitter, packet_loss_ratio, course_change_rate
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[QualityDatabase] Failed to prepare insert: \(errorMessage)")
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, record.id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_double(stmt, 2, record.timestamp.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 3, record.latitude)
        sqlite3_bind_double(stmt, 4, record.longitude)
        sqlite3_bind_double(stmt, 5, record.locationAccuracy)
        sqlite3_bind_double(stmt, 6, record.latencyMs)
        sqlite3_bind_int(stmt, 7, record.wasSuccessful ? 1 : 0)
        sqlite3_bind_text(stmt, 8, record.quality, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 9, record.connectionType, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        if let ssid = record.wifiSSID {
            sqlite3_bind_text(stmt, 10, ssid, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, 10)
        }

        if let rssi = record.wifiRSSI {
            sqlite3_bind_int(stmt, 11, Int32(rssi))
        } else {
            sqlite3_bind_null(stmt, 11)
        }

        sqlite3_bind_text(stmt, 12, record.interfaceName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 13, record.locationSource, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        if let speed = record.speedKmh {
            sqlite3_bind_double(stmt, 14, speed)
        } else {
            sqlite3_bind_null(stmt, 14)
        }

        if let altitude = record.altitude {
            sqlite3_bind_double(stmt, 15, altitude)
        } else {
            sqlite3_bind_null(stmt, 15)
        }

        if let jitter = record.jitter {
            sqlite3_bind_double(stmt, 16, jitter)
        } else {
            sqlite3_bind_null(stmt, 16)
        }

        if let packetLossRatio = record.packetLossRatio {
            sqlite3_bind_double(stmt, 17, packetLossRatio)
        } else {
            sqlite3_bind_null(stmt, 17)
        }

        if let courseChangeRate = record.courseChangeRate {
            sqlite3_bind_double(stmt, 18, courseChangeRate)
        } else {
            sqlite3_bind_null(stmt, 18)
        }

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("[QualityDatabase] Failed to insert record: \(errorMessage)")
        }
    }

    // MARK: - Update

    /// Updates the location fields of an existing record (used by backpropagation).
    func update(id: UUID, latitude: Double, longitude: Double, locationAccuracy: Double, locationSource: String) {
        let sql = """
            UPDATE quality_records
            SET latitude = ?, longitude = ?, location_accuracy = ?, location_source = ?
            WHERE id = ?
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[QualityDatabase] Failed to prepare update: \(errorMessage)")
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, latitude)
        sqlite3_bind_double(stmt, 2, longitude)
        sqlite3_bind_double(stmt, 3, locationAccuracy)
        sqlite3_bind_text(stmt, 4, locationSource, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 5, id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("[QualityDatabase] Failed to update record: \(errorMessage)")
        }
    }

    // MARK: - Query

    /// Returns all records in the database, ordered by timestamp descending.
    func queryAll() -> [QualityRecord] {
        return query(sql: "SELECT * FROM quality_records ORDER BY timestamp DESC")
    }

    /// Returns records within a geographic bounding box.
    func queryInRegion(
        minLat: Double, maxLat: Double,
        minLon: Double, maxLon: Double
    ) -> [QualityRecord] {
        let sql = """
            SELECT * FROM quality_records
            WHERE latitude BETWEEN ? AND ?
              AND longitude BETWEEN ? AND ?
            ORDER BY timestamp DESC
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, minLat)
        sqlite3_bind_double(stmt, 2, maxLat)
        sqlite3_bind_double(stmt, 3, minLon)
        sqlite3_bind_double(stmt, 4, maxLon)

        return readRows(from: stmt)
    }

    /// Returns records within a time range.
    func queryTimeRange(from start: Date, to end: Date) -> [QualityRecord] {
        let sql = """
            SELECT * FROM quality_records
            WHERE timestamp BETWEEN ? AND ?
            ORDER BY timestamp DESC
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, start.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 2, end.timeIntervalSince1970)

        return readRows(from: stmt)
    }

    /// Returns records at (0,0) — orphaned during GPS dropout, ordered by timestamp ascending.
    func queryOrphaned() -> [QualityRecord] {
        return query(sql: """
            SELECT * FROM quality_records
            WHERE latitude = 0.0 AND longitude = 0.0
            ORDER BY timestamp ASC
            """)
    }

    /// Returns the total number of records in the database.
    func recordCount() -> Int {
        let sql = "SELECT COUNT(*) FROM quality_records"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    // MARK: - Private Helpers

    private func query(sql: String) -> [QualityRecord] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[QualityDatabase] Failed to prepare query: \(errorMessage)")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        return readRows(from: stmt)
    }

    private func readRows(from stmt: OpaquePointer?) -> [QualityRecord] {
        var records: [QualityRecord] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let idStr = String(cString: sqlite3_column_text(stmt, 0))
            let timestamp = sqlite3_column_double(stmt, 1)
            let latitude = sqlite3_column_double(stmt, 2)
            let longitude = sqlite3_column_double(stmt, 3)
            let locationAccuracy = sqlite3_column_double(stmt, 4)
            let latencyMs = sqlite3_column_double(stmt, 5)
            let wasSuccessful = sqlite3_column_int(stmt, 6) != 0
            let quality = String(cString: sqlite3_column_text(stmt, 7))
            let connectionType = String(cString: sqlite3_column_text(stmt, 8))

            let wifiSSID: String? = sqlite3_column_type(stmt, 9) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 9))
                : nil

            let wifiRSSI: Int? = sqlite3_column_type(stmt, 10) != SQLITE_NULL
                ? Int(sqlite3_column_int(stmt, 10))
                : nil

            let interfaceName = String(cString: sqlite3_column_text(stmt, 11))

            let locationSource: String = sqlite3_column_type(stmt, 12) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 12))
                : "CoreLocation"

            let speedKmh: Double? = sqlite3_column_type(stmt, 13) != SQLITE_NULL
                ? sqlite3_column_double(stmt, 13)
                : nil

            let altitude: Double? = sqlite3_column_type(stmt, 14) != SQLITE_NULL
                ? sqlite3_column_double(stmt, 14)
                : nil

            let jitter: Double? = sqlite3_column_type(stmt, 15) != SQLITE_NULL
                ? sqlite3_column_double(stmt, 15)
                : nil

            let packetLossRatio: Double? = sqlite3_column_type(stmt, 16) != SQLITE_NULL
                ? sqlite3_column_double(stmt, 16)
                : nil

            let courseChangeRate: Double? = sqlite3_column_type(stmt, 17) != SQLITE_NULL
                ? sqlite3_column_double(stmt, 17)
                : nil

            let record = QualityRecord(
                id: UUID(uuidString: idStr) ?? UUID(),
                timestamp: Date(timeIntervalSince1970: timestamp),
                latitude: latitude,
                longitude: longitude,
                locationAccuracy: locationAccuracy,
                latencyMs: latencyMs,
                wasSuccessful: wasSuccessful,
                quality: quality,
                connectionType: connectionType,
                wifiSSID: wifiSSID,
                wifiRSSI: wifiRSSI,
                interfaceName: interfaceName,
                locationSource: locationSource,
                speedKmh: speedKmh,
                altitude: altitude,
                jitter: jitter,
                packetLossRatio: packetLossRatio,
                courseChangeRate: courseChangeRate
            )

            records.append(record)
        }

        return records
    }

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        var errorPtr: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorPtr)
        if result != SQLITE_OK {
            if let errorPtr = errorPtr {
                print("[QualityDatabase] SQL error: \(String(cString: errorPtr))")
                sqlite3_free(errorPtr)
            }
            return false
        }
        return true
    }

    private var errorMessage: String {
        if let msg = sqlite3_errmsg(db) {
            return String(cString: msg)
        }
        return "Unknown error"
    }
}
