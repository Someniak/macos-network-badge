// ---------------------------------------------------------
// ConnectionInfo.swift — Data models for network state
//
// These are simple value types that describe the current
// network connection. They're used by both the monitors
// (which produce data) and the views (which display it).
// ---------------------------------------------------------

import Foundation
import SwiftUI

// MARK: - Connection Type

/// Represents the kind of network connection currently active.
/// Each case maps to a real-world scenario you'd encounter
/// on a train, at a café, or at home.
enum ConnectionType: String, Equatable, Sendable {
    case wifi           = "WiFi"
    case ethernet       = "Ethernet"
    case usbTethering   = "USB Tethering"
    case hotspot        = "Personal Hotspot"
    case cellular       = "Cellular"
    case loopback       = "Loopback"
    case disconnected   = "Disconnected"
    case unknown        = "Unknown"

    /// SF Symbol name for each connection type (used in the UI)
    var symbolName: String {
        switch self {
        case .wifi:          return "wifi"
        case .ethernet:      return "cable.connector"
        case .usbTethering:  return "cable.connector.horizontal"
        case .hotspot:       return "iphone.radiowaves.left.and.right"
        case .cellular:      return "antenna.radiowaves.left.and.right"
        case .loopback:      return "arrow.triangle.2.circlepath"
        case .disconnected:  return "wifi.slash"
        case .unknown:       return "questionmark.circle"
        }
    }
}

// MARK: - Latency Quality

/// A human-friendly quality rating based on the measured latency.
/// Thresholds are tuned for typical train WiFi in Belgium/Europe.
enum LatencyQuality: String, Equatable, Sendable {
    case excellent = "Excellent"   // < 30ms  — fiber-like
    case good      = "Good"        // < 80ms  — normal browsing
    case fair      = "Fair"        // < 150ms — usable but sluggish
    case poor      = "Poor"        // < 300ms — video calls will struggle
    case bad       = "Bad"         // > 300ms — barely functional
    case unknown   = "Measuring…"  // no data yet

    /// Create a quality rating from a latency value in milliseconds
    static func from(latencyMs: Double) -> LatencyQuality {
        switch latencyMs {
        case ..<30:   return .excellent
        case ..<80:   return .good
        case ..<150:  return .fair
        case ..<300:  return .poor
        default:      return .bad
        }
    }

    /// Color name for SwiftUI (matches system colors)
    var colorName: String {
        switch self {
        case .excellent: return "green"
        case .good:      return "green"
        case .fair:      return "yellow"
        case .poor:      return "orange"
        case .bad:       return "red"
        case .unknown:   return "gray"
        }
    }

    /// Emoji indicator for the menu bar text
    var indicator: String {
        switch self {
        case .excellent: return "●"  // green dot (colored in UI)
        case .good:      return "●"
        case .fair:      return "●"
        case .poor:      return "●"
        case .bad:       return "●"
        case .unknown:   return "○"  // hollow = no data
        }
    }

    /// SwiftUI Color for this quality level — used in menu bar and popover
    var swiftUIColor: Color {
        switch self {
        case .excellent: return .green
        case .good:      return .green
        case .fair:      return .yellow
        case .poor:      return .orange
        case .bad:       return .red
        case .unknown:   return .gray
        }
    }
}

// MARK: - WiFi Signal Quality

/// A human-friendly rating of WiFi signal strength based on RSSI (dBm).
/// Typical RSSI values range from -30 (very strong) to -90 (very weak).
enum WiFiSignalQuality: String, Equatable, Sendable {
    case excellent = "Excellent"  // > -50 dBm
    case good      = "Good"       // -50 to -60 dBm
    case fair      = "Fair"       // -60 to -70 dBm
    case weak      = "Weak"       // < -70 dBm

    /// Determine signal quality from an RSSI value in dBm
    static func from(rssi: Int) -> WiFiSignalQuality {
        switch rssi {
        case (-50)...:   return .excellent
        case (-60)...:   return .good
        case (-70)...:   return .fair
        default:         return .weak
        }
    }

    /// SF Symbol name — tiered WiFi icons showing signal strength
    var symbolName: String {
        switch self {
        case .excellent: return "wifi"
        case .good:      return "wifi"
        case .fair:      return "wifi.exclamationmark"
        case .weak:      return "wifi.exclamationmark"
        }
    }

    /// SwiftUI Color for this signal quality level
    var swiftUIColor: Color {
        switch self {
        case .excellent: return .green
        case .good:      return .green
        case .fair:      return .yellow
        case .weak:      return .red
        }
    }
}

// MARK: - Location Source

/// Describes how a record's GPS coordinates were determined.
/// Used to visually differentiate location quality on the map.
enum LocationSource: String, Equatable, Sendable {
    case coreLocation  = "CoreLocation"     // Good GPS/Wi-Fi fix (accuracy <= 200m)
    case lowAccuracy   = "Low Accuracy"     // CoreLocation but accuracy > 200m
    case ipGeolocation = "IP Geolocation"   // Fallback from IP geolocation API
    case gps2ip        = "GPS2IP"           // iPhone GPS via GPS2IP app
    case interpolated  = "Interpolated"     // Backpropagated from speed estimation
    case none          = "None"             // No location available
}

// MARK: - Latency Sample

/// A single latency measurement at a point in time.
/// We keep a history of these to show trends.
struct LatencySample: Identifiable, Equatable, Sendable {
    let id = UUID()
    let timestamp: Date
    let latencyMs: Double      // round-trip time in milliseconds
    let wasSuccessful: Bool    // false if the ping timed out

    /// Human-readable latency string, e.g. "42 ms" or "Timeout"
    var displayText: String {
        if wasSuccessful {
            return "\(Int(latencyMs)) ms"
        } else {
            return "Timeout"
        }
    }
}

// MARK: - Quality Prediction

/// Spatial lookahead prediction based on historical records ahead.
struct QualityPrediction: Equatable {
    /// Expected quality at the projected position
    let expectedQuality: LatencyQuality
    /// Confidence in the prediction (0-1), based on sample count and age
    let confidence: Double
    /// How many minutes ahead this prediction covers
    let minutesAhead: Double
    /// Number of historical records used for prediction
    let sampleCount: Int
    /// Weighted average latency at the projected position
    let averageLatencyMs: Double
}

// MARK: - Connection Snapshot

/// A complete snapshot of the current network state.
/// This is what the UI reads to render everything.
struct ConnectionSnapshot: Equatable, Sendable {
    var connectionType: ConnectionType = .unknown
    var interfaceName: String = ""          // e.g. "en0", "bridge100"
    var wifiSSID: String? = nil             // e.g. "NMBS-WiFi" (nil if not on WiFi)
    var currentLatencyMs: Double? = nil     // nil if no measurement yet
    var averageLatencyMs: Double? = nil     // rolling average
    var quality: LatencyQuality = .unknown
    var isConnected: Bool = false

    /// Text shown directly in the menu bar (kept short!)
    var menuBarText: String {
        guard isConnected, let latency = currentLatencyMs else {
            return "○ --"
        }
        let quality = LatencyQuality.from(latencyMs: latency)
        return "\(quality.indicator) \(Int(latency))ms"
    }
}
