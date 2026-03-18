// ---------------------------------------------------------
// ConnectionInfoTests.swift — Tests for the data models
//
// These tests verify that our data types work correctly:
//   - LatencyQuality thresholds (what counts as "good" vs "bad")
//   - ConnectionType SF Symbol mapping
//   - LatencySample display formatting
//   - ConnectionSnapshot menu bar text generation
// ---------------------------------------------------------

import SwiftUI
import XCTest
@testable import NetworkBadge

final class ConnectionInfoTests: XCTestCase {

    // MARK: - LatencyQuality Threshold Tests

    /// Verify that latency values map to the correct quality ratings.
    /// These thresholds are tuned for European train WiFi.
    func testLatencyQualityThresholds() {
        // Excellent: under 30ms (fiber-like speeds)
        XCTAssertEqual(LatencyQuality.from(latencyMs: 5), .excellent)
        XCTAssertEqual(LatencyQuality.from(latencyMs: 29), .excellent)

        // Good: 30-79ms (normal browsing)
        XCTAssertEqual(LatencyQuality.from(latencyMs: 30), .good)
        XCTAssertEqual(LatencyQuality.from(latencyMs: 79), .good)

        // Fair: 80-149ms (usable but sluggish)
        XCTAssertEqual(LatencyQuality.from(latencyMs: 80), .fair)
        XCTAssertEqual(LatencyQuality.from(latencyMs: 149), .fair)

        // Poor: 150-299ms (video calls will struggle)
        XCTAssertEqual(LatencyQuality.from(latencyMs: 150), .poor)
        XCTAssertEqual(LatencyQuality.from(latencyMs: 299), .poor)

        // Bad: 300ms+ (barely functional)
        XCTAssertEqual(LatencyQuality.from(latencyMs: 300), .bad)
        XCTAssertEqual(LatencyQuality.from(latencyMs: 1000), .bad)
    }

    /// Edge case: zero latency should be excellent
    func testZeroLatencyIsExcellent() {
        XCTAssertEqual(LatencyQuality.from(latencyMs: 0), .excellent)
    }

    // MARK: - LatencyQuality Color Tests

    func testQualityColors() {
        XCTAssertEqual(LatencyQuality.excellent.colorName, "green")
        XCTAssertEqual(LatencyQuality.good.colorName, "green")
        XCTAssertEqual(LatencyQuality.fair.colorName, "yellow")
        XCTAssertEqual(LatencyQuality.poor.colorName, "orange")
        XCTAssertEqual(LatencyQuality.bad.colorName, "red")
        XCTAssertEqual(LatencyQuality.unknown.colorName, "gray")
    }

    // MARK: - ConnectionType Tests

    /// Every connection type should have an SF Symbol name
    func testConnectionTypeSymbols() {
        // Just verify they're non-empty (valid SF Symbol names)
        let allTypes: [ConnectionType] = [
            .wifi, .ethernet, .usbTethering, .hotspot,
            .cellular, .loopback, .disconnected, .unknown,
        ]
        for type in allTypes {
            XCTAssertFalse(
                type.symbolName.isEmpty,
                "\(type.rawValue) should have a symbol name"
            )
        }
    }

    /// Connection types should have human-readable raw values
    func testConnectionTypeDisplayNames() {
        XCTAssertEqual(ConnectionType.wifi.rawValue, "WiFi")
        XCTAssertEqual(ConnectionType.ethernet.rawValue, "Ethernet")
        XCTAssertEqual(ConnectionType.usbTethering.rawValue, "USB Tethering")
        XCTAssertEqual(ConnectionType.disconnected.rawValue, "Disconnected")
    }

    // MARK: - LatencySample Tests

    /// Successful samples show "42 ms" format
    func testLatencySampleDisplayTextSuccess() {
        let sample = LatencySample(
            timestamp: Date(),
            latencyMs: 42.7,
            wasSuccessful: true
        )
        XCTAssertEqual(sample.displayText, "42 ms")
    }

    /// Failed samples show "Timeout"
    func testLatencySampleDisplayTextTimeout() {
        let sample = LatencySample(
            timestamp: Date(),
            latencyMs: 0,
            wasSuccessful: false
        )
        XCTAssertEqual(sample.displayText, "Timeout")
    }

    /// Samples with very high latency should still format correctly
    func testLatencySampleHighLatency() {
        let sample = LatencySample(
            timestamp: Date(),
            latencyMs: 1234.5,
            wasSuccessful: true
        )
        XCTAssertEqual(sample.displayText, "1234 ms")
    }

    // MARK: - ConnectionSnapshot Tests

    /// Menu bar text when connected with latency
    func testMenuBarTextConnected() {
        var snapshot = ConnectionSnapshot()
        snapshot.isConnected = true
        snapshot.currentLatencyMs = 42.0
        snapshot.quality = .good

        let text = snapshot.menuBarText
        XCTAssertTrue(text.contains("42"), "Should show latency value")
        XCTAssertTrue(text.contains("ms"), "Should show 'ms' unit")
    }

    /// Menu bar text when disconnected
    func testMenuBarTextDisconnected() {
        var snapshot = ConnectionSnapshot()
        snapshot.isConnected = false
        snapshot.currentLatencyMs = nil

        XCTAssertEqual(snapshot.menuBarText, "○ --")
    }

    /// Menu bar text when connected but no measurement yet
    func testMenuBarTextNoMeasurement() {
        var snapshot = ConnectionSnapshot()
        snapshot.isConnected = true
        snapshot.currentLatencyMs = nil

        XCTAssertEqual(snapshot.menuBarText, "○ --")
    }

    /// Default snapshot should show unknown state
    func testDefaultSnapshot() {
        let snapshot = ConnectionSnapshot()
        XCTAssertEqual(snapshot.connectionType, .unknown)
        XCTAssertEqual(snapshot.quality, .unknown)
        XCTAssertFalse(snapshot.isConnected)
        XCTAssertNil(snapshot.currentLatencyMs)
        XCTAssertNil(snapshot.wifiSSID)
    }

    // MARK: - LatencyQuality SwiftUI Color Tests

    /// Every quality level should return a SwiftUI Color
    func testQualitySwiftUIColors() {
        XCTAssertEqual(LatencyQuality.excellent.swiftUIColor, Color.green)
        XCTAssertEqual(LatencyQuality.good.swiftUIColor, Color.green)
        XCTAssertEqual(LatencyQuality.fair.swiftUIColor, Color.yellow)
        XCTAssertEqual(LatencyQuality.poor.swiftUIColor, Color.orange)
        XCTAssertEqual(LatencyQuality.bad.swiftUIColor, Color.red)
        XCTAssertEqual(LatencyQuality.unknown.swiftUIColor, Color.gray)
    }

    // MARK: - WiFiSignalQuality Tests

    /// Verify RSSI values map to correct signal quality levels
    func testWiFiSignalQualityThresholds() {
        // Excellent: >= -50 dBm
        XCTAssertEqual(WiFiSignalQuality.from(rssi: -30), .excellent)
        XCTAssertEqual(WiFiSignalQuality.from(rssi: -50), .excellent)

        // Good: -51 to -60 dBm
        XCTAssertEqual(WiFiSignalQuality.from(rssi: -51), .good)
        XCTAssertEqual(WiFiSignalQuality.from(rssi: -60), .good)

        // Fair: -61 to -70 dBm
        XCTAssertEqual(WiFiSignalQuality.from(rssi: -61), .fair)
        XCTAssertEqual(WiFiSignalQuality.from(rssi: -70), .fair)

        // Weak: < -70 dBm
        XCTAssertEqual(WiFiSignalQuality.from(rssi: -71), .weak)
        XCTAssertEqual(WiFiSignalQuality.from(rssi: -90), .weak)
    }

    /// WiFi signal quality should have SF Symbol names
    func testWiFiSignalQualitySymbols() {
        let allQualities: [WiFiSignalQuality] = [.excellent, .good, .fair, .weak]
        for quality in allQualities {
            XCTAssertFalse(
                quality.symbolName.isEmpty,
                "\(quality.rawValue) should have a symbol name"
            )
        }
    }

    /// WiFi signal quality should have SwiftUI colors
    func testWiFiSignalQualityColors() {
        XCTAssertEqual(WiFiSignalQuality.excellent.swiftUIColor, Color.green)
        XCTAssertEqual(WiFiSignalQuality.good.swiftUIColor, Color.green)
        XCTAssertEqual(WiFiSignalQuality.fair.swiftUIColor, Color.yellow)
        XCTAssertEqual(WiFiSignalQuality.weak.swiftUIColor, Color.red)
    }

    /// Edge case: very strong signal
    func testVeryStrongWiFiSignal() {
        XCTAssertEqual(WiFiSignalQuality.from(rssi: -10), .excellent)
    }

    /// Edge case: very weak signal
    func testVeryWeakWiFiSignal() {
        XCTAssertEqual(WiFiSignalQuality.from(rssi: -100), .weak)
    }
}
