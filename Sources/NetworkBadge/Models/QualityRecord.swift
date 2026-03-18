// ---------------------------------------------------------
// QualityRecord.swift — GPS-tagged network quality measurement
//
// Each record captures a network quality measurement along
// with the GPS coordinates where it was taken. These records
// are stored permanently for future predictive analysis.
// ---------------------------------------------------------

import Foundation

/// A single GPS-tagged network quality measurement.
/// Designed for persistent storage and future ML analysis.
struct QualityRecord: Identifiable, Equatable, Sendable {

    /// Unique identifier for this record
    let id: UUID

    /// When this measurement was taken
    let timestamp: Date

    /// GPS latitude in degrees
    let latitude: Double

    /// GPS longitude in degrees
    let longitude: Double

    /// Horizontal accuracy of the GPS reading in meters
    /// (lower = more accurate, e.g. 5m vs 65m)
    let locationAccuracy: Double

    /// Round-trip latency in milliseconds (0 if timed out)
    let latencyMs: Double

    /// Whether the measurement succeeded or timed out
    let wasSuccessful: Bool

    /// Quality rating at time of measurement
    let quality: String

    /// Type of network connection (WiFi, Cellular, etc.)
    let connectionType: String

    /// WiFi network name, if applicable
    let wifiSSID: String?

    /// WiFi signal strength in dBm, if applicable
    let wifiRSSI: Int?

    /// System network interface name (e.g. "en0")
    let interfaceName: String

    /// How the GPS coordinates were determined (CoreLocation, IP, Interpolated, etc.)
    let locationSource: String

    /// Derived quality color for map display
    var qualityLevel: LatencyQuality {
        LatencyQuality(rawValue: quality) ?? .unknown
    }

    /// Derived location source enum
    var locationSourceLevel: LocationSource {
        LocationSource(rawValue: locationSource) ?? .coreLocation
    }

    /// Create a record from current monitor state and GPS coordinates
    static func from(
        latitude: Double,
        longitude: Double,
        locationAccuracy: Double,
        latencyMs: Double,
        wasSuccessful: Bool,
        connectionType: ConnectionType,
        wifiSSID: String?,
        wifiRSSI: Int?,
        interfaceName: String,
        locationSource: LocationSource = .coreLocation
    ) -> QualityRecord {
        let quality: LatencyQuality = wasSuccessful
            ? LatencyQuality.from(latencyMs: latencyMs)
            : .bad

        return QualityRecord(
            id: UUID(),
            timestamp: Date(),
            latitude: latitude,
            longitude: longitude,
            locationAccuracy: locationAccuracy,
            latencyMs: latencyMs,
            wasSuccessful: wasSuccessful,
            quality: quality.rawValue,
            connectionType: connectionType.rawValue,
            wifiSSID: wifiSSID,
            wifiRSSI: wifiRSSI,
            interfaceName: interfaceName,
            locationSource: locationSource.rawValue
        )
    }
}
