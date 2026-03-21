// ---------------------------------------------------------
// LatencyMonitorTests.swift — Tests for latency measurement
//
// These tests verify the LatencyMonitor's sample management,
// average calculation, and quality derivation. We test the
// logic WITHOUT making real network requests.
// ---------------------------------------------------------

import XCTest
@testable import NetworkBadge

final class LatencyMonitorTests: XCTestCase {

    // MARK: - Sample Recording

    /// Recording a successful sample should update current latency
    func testRecordSuccessfulSample() {
        let monitor = LatencyMonitor()

        let sample = LatencySample(
            timestamp: Date(),
            latencyMs: 42.0,
            wasSuccessful: true
        )
        monitor.recordSample(sample)

        XCTAssertEqual(monitor.currentLatencyMs, 42.0)
        XCTAssertEqual(monitor.quality, .good)  // 42ms is "good"
        XCTAssertEqual(monitor.samples.count, 1)
    }

    /// Recording a failed sample should clear current latency
    func testRecordFailedSample() {
        let monitor = LatencyMonitor()

        let sample = LatencySample(
            timestamp: Date(),
            latencyMs: 0,
            wasSuccessful: false
        )
        monitor.recordSample(sample)

        XCTAssertNil(monitor.currentLatencyMs)
        XCTAssertEqual(monitor.quality, .bad)
    }

    // MARK: - Average Calculation

    /// Average should be calculated from successful samples only
    func testAverageCalculation() {
        let monitor = LatencyMonitor()

        // Add 3 successful samples: 40, 50, 60 → average = 50
        let samples = [40.0, 50.0, 60.0]
        for latency in samples {
            monitor.recordSample(LatencySample(
                timestamp: Date(),
                latencyMs: latency,
                wasSuccessful: true
            ))
        }

        XCTAssertNotNil(monitor.averageLatencyMs)
        XCTAssertEqual(monitor.averageLatencyMs!, 50.0, accuracy: 0.1)
    }

    /// Failed samples should NOT affect the average
    func testAverageIgnoresFailedSamples() {
        let monitor = LatencyMonitor()

        // Add successful sample: 40ms
        monitor.recordSample(LatencySample(
            timestamp: Date(),
            latencyMs: 40.0,
            wasSuccessful: true
        ))

        // Add failed sample (should not change average)
        monitor.recordSample(LatencySample(
            timestamp: Date(),
            latencyMs: 0,
            wasSuccessful: false
        ))

        // Add successful sample: 60ms
        monitor.recordSample(LatencySample(
            timestamp: Date(),
            latencyMs: 60.0,
            wasSuccessful: true
        ))

        // Average should be (40 + 60) / 2 = 50
        XCTAssertNotNil(monitor.averageLatencyMs)
        XCTAssertEqual(monitor.averageLatencyMs!, 50.0, accuracy: 0.1)
    }

    /// When all samples fail, average should be nil
    func testAverageWithAllFailedSamples() {
        let monitor = LatencyMonitor()

        monitor.recordSample(LatencySample(
            timestamp: Date(),
            latencyMs: 0,
            wasSuccessful: false
        ))

        XCTAssertNil(monitor.averageLatencyMs)
    }

    // MARK: - Sample History Limit

    /// Sample history should be capped at maxSampleCount
    func testSampleHistoryLimit() {
        let monitor = LatencyMonitor(maxSamples: 5)

        // Add 8 samples — only 5 should be kept
        for i in 1...8 {
            monitor.recordSample(LatencySample(
                timestamp: Date(),
                latencyMs: Double(i * 10),
                wasSuccessful: true
            ))
        }

        XCTAssertEqual(monitor.samples.count, 5)
    }

    /// Newest samples should be at the front of the list
    func testNewestSamplesFirst() {
        let monitor = LatencyMonitor()

        monitor.recordSample(LatencySample(
            timestamp: Date(),
            latencyMs: 10.0,
            wasSuccessful: true
        ))
        monitor.recordSample(LatencySample(
            timestamp: Date(),
            latencyMs: 20.0,
            wasSuccessful: true
        ))

        // The 20ms sample should be first (newest)
        XCTAssertEqual(monitor.samples.first?.latencyMs, 20.0)
    }

    // MARK: - Quality Mapping

    /// Verify quality correctly maps from latency
    func testQualityMapping() {
        let monitor = LatencyMonitor()

        // Excellent: 10ms
        monitor.recordSample(LatencySample(
            timestamp: Date(), latencyMs: 10.0, wasSuccessful: true
        ))
        XCTAssertEqual(monitor.quality, .excellent)

        // Poor: 200ms
        monitor.recordSample(LatencySample(
            timestamp: Date(), latencyMs: 200.0, wasSuccessful: true
        ))
        XCTAssertEqual(monitor.quality, .poor)

        // Bad: 500ms
        monitor.recordSample(LatencySample(
            timestamp: Date(), latencyMs: 500.0, wasSuccessful: true
        ))
        XCTAssertEqual(monitor.quality, .bad)
    }

    // MARK: - Initial State

    /// Monitor should start with no data
    func testInitialState() {
        let monitor = LatencyMonitor()

        XCTAssertNil(monitor.currentLatencyMs)
        XCTAssertNil(monitor.averageLatencyMs)
        XCTAssertEqual(monitor.quality, .unknown)
        XCTAssertTrue(monitor.samples.isEmpty)
        XCTAssertFalse(monitor.isMeasuring)
    }

    // MARK: - Configuration

    /// Verify custom configuration is respected
    func testCustomConfiguration() {
        let monitor = LatencyMonitor(
            interval: 5.0,
            timeout: 15.0,
            maxSamples: 50
        )

        XCTAssertEqual(monitor.measurementInterval, 5.0)
        XCTAssertEqual(monitor.timeoutInterval, 15.0)
        XCTAssertEqual(monitor.maxSampleCount, 50)
    }

    // MARK: - Packet Loss

    /// Packet loss should be 0% when all samples succeed
    func testPacketLossAllSuccessful() {
        let monitor = LatencyMonitor()
        for latency in [30.0, 40.0, 50.0] {
            monitor.recordSample(LatencySample(
                timestamp: Date(), latencyMs: latency, wasSuccessful: true
            ))
        }
        XCTAssertEqual(monitor.packetLossPercent, 0.0, accuracy: 0.01)
    }

    /// Packet loss should be 100% when all samples fail
    func testPacketLossAllFailed() {
        let monitor = LatencyMonitor()
        for _ in 1...4 {
            monitor.recordSample(LatencySample(
                timestamp: Date(), latencyMs: 0, wasSuccessful: false
            ))
        }
        XCTAssertEqual(monitor.packetLossPercent, 100.0, accuracy: 0.01)
    }

    /// Packet loss with mixed results
    func testPacketLossMixed() {
        let monitor = LatencyMonitor()
        // 2 successful, 2 failed → 50%
        monitor.recordSample(LatencySample(timestamp: Date(), latencyMs: 40, wasSuccessful: true))
        monitor.recordSample(LatencySample(timestamp: Date(), latencyMs: 0, wasSuccessful: false))
        monitor.recordSample(LatencySample(timestamp: Date(), latencyMs: 50, wasSuccessful: true))
        monitor.recordSample(LatencySample(timestamp: Date(), latencyMs: 0, wasSuccessful: false))
        XCTAssertEqual(monitor.packetLossPercent, 50.0, accuracy: 0.01)
    }

    /// Packet loss should be 0 with no samples
    func testPacketLossEmpty() {
        let monitor = LatencyMonitor()
        XCTAssertEqual(monitor.packetLossPercent, 0.0)
    }

    // MARK: - Jitter

    /// Jitter should be nil with fewer than 2 successful samples
    func testJitterInsufficientSamples() {
        let monitor = LatencyMonitor()
        monitor.recordSample(LatencySample(
            timestamp: Date(), latencyMs: 40.0, wasSuccessful: true
        ))
        XCTAssertNil(monitor.jitterMs)
    }

    /// Jitter should be nil with no samples
    func testJitterEmpty() {
        let monitor = LatencyMonitor()
        XCTAssertNil(monitor.jitterMs)
    }

    /// Jitter with constant latency should be 0
    func testJitterConstantLatency() {
        let monitor = LatencyMonitor()
        for _ in 1...5 {
            monitor.recordSample(LatencySample(
                timestamp: Date(), latencyMs: 50.0, wasSuccessful: true
            ))
        }
        XCTAssertEqual(monitor.jitterMs!, 0.0, accuracy: 0.01)
    }

    /// Jitter with varying latency
    func testJitterVaryingLatency() {
        let monitor = LatencyMonitor()
        // Samples: 40, 60, 40, 60
        // Diffs: |60-40|=20, |40-60|=20, |60-40|=20
        // Average jitter = 20
        for latency in [40.0, 60.0, 40.0, 60.0] {
            monitor.recordSample(LatencySample(
                timestamp: Date(), latencyMs: latency, wasSuccessful: true
            ))
        }
        XCTAssertEqual(monitor.jitterMs!, 20.0, accuracy: 0.01)
    }

    /// Jitter should skip failed samples
    func testJitterIgnoresFailedSamples() {
        let monitor = LatencyMonitor()
        // Successful: 40, then fail, then 60 → jitter = |60-40| = 20
        monitor.recordSample(LatencySample(timestamp: Date(), latencyMs: 40.0, wasSuccessful: true))
        monitor.recordSample(LatencySample(timestamp: Date(), latencyMs: 0, wasSuccessful: false))
        monitor.recordSample(LatencySample(timestamp: Date(), latencyMs: 60.0, wasSuccessful: true))
        XCTAssertEqual(monitor.jitterMs!, 20.0, accuracy: 0.01)
    }

    // MARK: - Quality Score

    /// Quality score should be nil with no samples
    func testQualityScoreEmpty() {
        let monitor = LatencyMonitor()
        XCTAssertNil(monitor.qualityScore)
    }

    /// Excellent connection: low latency, no loss → score near 100
    func testQualityScoreExcellent() {
        let monitor = LatencyMonitor()
        for latency in [10.0, 12.0, 11.0, 10.0, 13.0] {
            monitor.recordSample(LatencySample(
                timestamp: Date(), latencyMs: latency, wasSuccessful: true
            ))
        }
        let score = monitor.qualityScore!
        XCTAssertGreaterThanOrEqual(score, 85)
        XCTAssertLessThanOrEqual(score, 100)
    }

    /// Terrible connection: high latency + packet loss → score near 0
    func testQualityScoreTerrible() {
        let monitor = LatencyMonitor()
        // Mix of very high latency and timeouts
        monitor.recordSample(LatencySample(timestamp: Date(), latencyMs: 400, wasSuccessful: true))
        monitor.recordSample(LatencySample(timestamp: Date(), latencyMs: 0, wasSuccessful: false))
        monitor.recordSample(LatencySample(timestamp: Date(), latencyMs: 0, wasSuccessful: false))
        monitor.recordSample(LatencySample(timestamp: Date(), latencyMs: 500, wasSuccessful: true))
        let score = monitor.qualityScore!
        XCTAssertLessThanOrEqual(score, 25)
    }

    /// All timeouts should give score of 0
    func testQualityScoreAllTimeouts() {
        let monitor = LatencyMonitor()
        for _ in 1...5 {
            monitor.recordSample(LatencySample(
                timestamp: Date(), latencyMs: 0, wasSuccessful: false
            ))
        }
        XCTAssertEqual(monitor.qualityScore!, 0)
    }

    /// Score should be clamped to 0-100
    func testQualityScoreClamped() {
        let monitor = LatencyMonitor()
        // Very low latency
        for _ in 1...10 {
            monitor.recordSample(LatencySample(
                timestamp: Date(), latencyMs: 1.0, wasSuccessful: true
            ))
        }
        let score = monitor.qualityScore!
        XCTAssertGreaterThanOrEqual(score, 0)
        XCTAssertLessThanOrEqual(score, 100)
    }
}
