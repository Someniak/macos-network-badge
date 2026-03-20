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

    // MARK: - Jitter & Packet Loss

    /// Jitter should be nil with fewer than 2 successful samples
    func testJitterNilWithFewSamples() {
        let monitor = LatencyMonitor()
        XCTAssertNil(monitor.jitter)

        monitor.recordSample(LatencySample(timestamp: Date(), latencyMs: 42.0, wasSuccessful: true))
        XCTAssertNil(monitor.jitter)
    }

    /// Jitter should be the stddev of recent successful latencies
    func testJitterCalculation() {
        let monitor = LatencyMonitor()

        // Add samples: 40, 50, 60 → stddev = sqrt(((−10)²+0²+10²)/3) ≈ 8.16
        for latency in [40.0, 50.0, 60.0] {
            monitor.recordSample(LatencySample(timestamp: Date(), latencyMs: latency, wasSuccessful: true))
        }

        let jitter = monitor.jitter
        XCTAssertNotNil(jitter)
        XCTAssertGreaterThan(jitter!, 7.0)
        XCTAssertLessThan(jitter!, 10.0)
    }

    /// Packet loss should be nil with no samples
    func testPacketLossNilWithNoSamples() {
        let monitor = LatencyMonitor()
        XCTAssertNil(monitor.packetLossRatio)
    }

    /// Packet loss should reflect failed/total ratio
    func testPacketLossRatio() {
        let monitor = LatencyMonitor()

        // 3 success, 2 failed → 2/5 = 0.4
        for latency in [40.0, 50.0, 60.0] {
            monitor.recordSample(LatencySample(timestamp: Date(), latencyMs: latency, wasSuccessful: true))
        }
        monitor.recordSample(LatencySample(timestamp: Date(), latencyMs: 0, wasSuccessful: false))
        monitor.recordSample(LatencySample(timestamp: Date(), latencyMs: 0, wasSuccessful: false))

        let loss = monitor.packetLossRatio
        XCTAssertNotNil(loss)
        XCTAssertEqual(loss!, 0.4, accuracy: 0.01)
    }

    // MARK: - Configuration

    /// Verify custom configuration is respected
    func testCustomConfiguration() {
        let monitor = LatencyMonitor(
            timeout: 15.0,
            maxSamples: 50
        )

        XCTAssertEqual(monitor.timeoutInterval, 15.0)
        XCTAssertEqual(monitor.maxSampleCount, 50)
    }
}
