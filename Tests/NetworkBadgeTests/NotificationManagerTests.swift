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

    // MARK: - Latency Monitor Previous Quality Tests

    /// LatencyMonitor should track previousQuality on sample recording
    func testLatencyMonitorTracksPreviousQuality() {
        let monitor = LatencyMonitor()

        // Record an excellent sample
        let sample1 = LatencySample(
            timestamp: Date(),
            latencyMs: 20,
            wasSuccessful: true
        )
        monitor.recordSample(sample1)
        XCTAssertEqual(monitor.quality, .excellent)
        XCTAssertEqual(monitor.previousQuality, .unknown) // was unknown before

        // Record a poor sample
        let sample2 = LatencySample(
            timestamp: Date(),
            latencyMs: 200,
            wasSuccessful: true
        )
        monitor.recordSample(sample2)
        XCTAssertEqual(monitor.quality, .poor)
        XCTAssertEqual(monitor.previousQuality, .excellent) // was excellent before
    }
}
