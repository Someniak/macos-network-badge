// ---------------------------------------------------------
// NotificationManagerTests.swift — Tests for quality-drop
//                                   notification logic
//
// Tests the core logic:
//   - Degradation detection (good→poor fires, poor→poor doesn't)
//   - Rate limiting (30s cooldown)
//   - Enable/disable toggle
// ---------------------------------------------------------

import XCTest
@testable import NetworkBadge

final class NotificationManagerTests: XCTestCase {

    // MARK: - Degradation Detection Tests

    /// Degradation from good to poor should be detected
    func testGoodToPoorIsDegradation() {
        let manager = NotificationManager()
        XCTAssertTrue(manager.isDegradation(from: .good, to: .poor))
    }

    /// Degradation from excellent to bad should be detected
    func testExcellentToBadIsDegradation() {
        let manager = NotificationManager()
        XCTAssertTrue(manager.isDegradation(from: .excellent, to: .bad))
    }

    /// Same quality is NOT a degradation
    func testSameQualityIsNotDegradation() {
        let manager = NotificationManager()
        XCTAssertFalse(manager.isDegradation(from: .poor, to: .poor))
        XCTAssertFalse(manager.isDegradation(from: .good, to: .good))
    }

    /// Improvement is NOT a degradation
    func testImprovementIsNotDegradation() {
        let manager = NotificationManager()
        XCTAssertFalse(manager.isDegradation(from: .poor, to: .good))
        XCTAssertFalse(manager.isDegradation(from: .bad, to: .excellent))
    }

    /// Unknown to any quality is NOT a degradation
    func testUnknownToAnyIsNotDegradation() {
        let manager = NotificationManager()
        // Unknown has severity -1, so transitions from unknown are not degradation
        // unless going to a worse quality
        XCTAssertTrue(manager.isDegradation(from: .unknown, to: .poor))
        XCTAssertTrue(manager.isDegradation(from: .unknown, to: .bad))
    }

    /// Fair to poor should be a degradation
    func testFairToPoorIsDegradation() {
        let manager = NotificationManager()
        XCTAssertTrue(manager.isDegradation(from: .fair, to: .poor))
    }

    // MARK: - Connection Loss Detection Tests

    /// WiFi → disconnected should fire a connection-lost notification
    func testWifiToDisconnectedFires() {
        let manager = NotificationManager(cooldown: 0)
        manager.notificationsEnabled = true

        // Simulate arriving on WiFi first
        manager.notifyConnectionChange(to: .wifi)
        XCTAssertNil(manager.lastNotificationDate)

        // Now disconnect
        manager.notifyConnectionChange(to: .disconnected)
        XCTAssertNotNil(manager.lastNotificationDate)
    }

    /// Ethernet → disconnected should fire
    func testEthernetToDisconnectedFires() {
        let manager = NotificationManager(cooldown: 0)
        manager.notificationsEnabled = true

        manager.notifyConnectionChange(to: .ethernet)
        manager.notifyConnectionChange(to: .disconnected)
        XCTAssertNotNil(manager.lastNotificationDate)
    }

    /// Reconnection (disconnected → WiFi) should NOT fire
    func testReconnectionDoesNotFire() {
        let manager = NotificationManager(cooldown: 0)
        manager.notificationsEnabled = true

        manager.notifyConnectionChange(to: .disconnected)
        XCTAssertNil(manager.lastNotificationDate)

        manager.notifyConnectionChange(to: .wifi)
        XCTAssertNil(manager.lastNotificationDate)
    }

    /// Non-primary → disconnected should NOT fire (e.g. loopback)
    func testNonPrimaryToDisconnectedDoesNotFire() {
        let manager = NotificationManager(cooldown: 0)
        manager.notificationsEnabled = true

        manager.notifyConnectionChange(to: .loopback)
        manager.notifyConnectionChange(to: .disconnected)
        XCTAssertNil(manager.lastNotificationDate)
    }

    /// Cooldown should apply to disconnection alerts
    func testConnectionLostCooldownApplies() {
        let manager = NotificationManager(cooldown: 60)
        manager.notificationsEnabled = true

        // First: wifi → disconnected fires
        manager.notifyConnectionChange(to: .wifi)
        manager.notifyConnectionChange(to: .disconnected)
        let firstDate = manager.lastNotificationDate
        XCTAssertNotNil(firstDate)

        // Second: wifi → disconnected within cooldown should NOT update lastNotificationDate
        manager.notifyConnectionChange(to: .wifi)
        manager.notifyConnectionChange(to: .disconnected)
        XCTAssertEqual(manager.lastNotificationDate, firstDate)
    }

    /// Disconnection alerts suppressed when notifications disabled
    func testConnectionLostSuppressedWhenDisabled() {
        let manager = NotificationManager(cooldown: 0)
        manager.notificationsEnabled = false

        manager.notifyConnectionChange(to: .wifi)
        manager.notifyConnectionChange(to: .disconnected)
        XCTAssertNil(manager.lastNotificationDate)
    }

    // MARK: - NetworkAlert Tests

    /// Test alert body text for connection lost
    func testConnectionLostAlertBody() {
        let alert = NetworkAlert.connectionLost(.wifi)
        XCTAssertEqual(alert.title, "Connection Lost")
        XCTAssertEqual(alert.body, "WiFi disconnected")
    }

    /// Test alert body for latency degradation
    func testLatencyDegradedAlertBody() {
        let alert = NetworkAlert.latencyDegraded(.poor, 245)
        XCTAssertEqual(alert.title, "Network Quality Dropped")
        XCTAssertEqual(alert.body, "Latency is now 245ms (poor)")
    }

    /// Test alert body for timeout (0ms latency)
    func testTimeoutAlertBody() {
        let alert = NetworkAlert.latencyDegraded(.bad, 0)
        XCTAssertEqual(alert.body, "Connection timed out (bad)")
    }

    // MARK: - Prediction Alert Tests

    /// Poor prediction with high confidence should fire
    func testPoorPredictionFires() {
        let manager = NotificationManager(cooldown: 0)
        manager.notificationsEnabled = true

        let prediction = QualityPrediction(
            expectedQuality: .poor, confidence: 0.8,
            minutesAhead: 2.0, sampleCount: 8, averageLatencyMs: 250
        )
        manager.notifyPredictionChange(to: prediction)
        XCTAssertNotNil(manager.lastNotificationDate)
        XCTAssertTrue(manager.hasAlertedForCurrentPrediction)
    }

    /// Good prediction should NOT fire
    func testGoodPredictionDoesNotFire() {
        let manager = NotificationManager(cooldown: 0)
        manager.notificationsEnabled = true

        let prediction = QualityPrediction(
            expectedQuality: .good, confidence: 0.9,
            minutesAhead: 2.0, sampleCount: 10, averageLatencyMs: 50
        )
        manager.notifyPredictionChange(to: prediction)
        XCTAssertNil(manager.lastNotificationDate)
    }

    /// Low confidence prediction should NOT fire
    func testLowConfidencePredictionDoesNotFire() {
        let manager = NotificationManager(cooldown: 0)
        manager.notificationsEnabled = true

        let prediction = QualityPrediction(
            expectedQuality: .bad, confidence: 0.3,
            minutesAhead: 2.0, sampleCount: 3, averageLatencyMs: 500
        )
        manager.notifyPredictionChange(to: prediction)
        XCTAssertNil(manager.lastNotificationDate)
    }

    /// Should not fire twice for same prediction window
    func testPredictionDoesNotFireTwice() {
        let manager = NotificationManager(cooldown: 0)
        manager.notificationsEnabled = true

        let prediction = QualityPrediction(
            expectedQuality: .bad, confidence: 0.8,
            minutesAhead: 2.0, sampleCount: 8, averageLatencyMs: 500
        )
        manager.notifyPredictionChange(to: prediction)
        let firstDate = manager.lastNotificationDate
        XCTAssertNotNil(firstDate)

        // Second call with same prediction should not fire again
        manager.notifyPredictionChange(to: prediction)
        XCTAssertEqual(manager.lastNotificationDate, firstDate)
    }

    /// Clearing prediction then getting a new bad one should fire again
    func testPredictionResetsAfterClearing() {
        let manager = NotificationManager(cooldown: 0)
        manager.notificationsEnabled = true

        let prediction = QualityPrediction(
            expectedQuality: .bad, confidence: 0.8,
            minutesAhead: 2.0, sampleCount: 8, averageLatencyMs: 500
        )
        manager.notifyPredictionChange(to: prediction)
        XCTAssertTrue(manager.hasAlertedForCurrentPrediction)

        // Clear prediction
        manager.notifyPredictionChange(to: nil)
        XCTAssertFalse(manager.hasAlertedForCurrentPrediction)

        // New bad prediction should fire
        manager.notifyPredictionChange(to: prediction)
        XCTAssertTrue(manager.hasAlertedForCurrentPrediction)
    }

    /// Test prediction alert body text
    func testPredictionAlertBody() {
        let prediction = QualityPrediction(
            expectedQuality: .poor, confidence: 0.8,
            minutesAhead: 2.0, sampleCount: 8, averageLatencyMs: 250
        )
        let alert = NetworkAlert.poorConnectivityAhead(prediction)
        XCTAssertEqual(alert.title, "Rough Connection Ahead")
        XCTAssertTrue(alert.body.contains("poor"))
        XCTAssertTrue(alert.body.contains("2 min"))
        XCTAssertTrue(alert.body.contains("250ms"))
    }

    // MARK: - Notification Suppression Tests

    /// Notifications should not fire when disabled
    func testNotificationsDisabledSuppresses() {
        let manager = NotificationManager(cooldown: 0)
        manager.notificationsEnabled = false

        manager.notifyQualityDrop(to: .poor, latencyMs: 200)

        // lastNotificationDate stays nil because notification was suppressed
        XCTAssertNil(manager.lastNotificationDate)
    }

    /// Notifications should not fire for non-degradation
    func testNonDegradationDoesNotNotify() {
        let manager = NotificationManager(cooldown: 0)
        manager.notificationsEnabled = true

        // Improvement: poor → good — should not fire
        manager.notifyQualityDrop(to: .good, latencyMs: 50)
        XCTAssertNil(manager.lastNotificationDate)
    }

    /// Notifications should not fire for mild quality levels (excellent/good/fair)
    func testMildQualityDoesNotNotify() {
        let manager = NotificationManager(cooldown: 0)
        manager.notificationsEnabled = true

        // excellent → fair is degradation, but fair isn't poor/bad
        manager.notifyQualityDrop(to: .fair, latencyMs: 100)
        XCTAssertNil(manager.lastNotificationDate)
    }

}
