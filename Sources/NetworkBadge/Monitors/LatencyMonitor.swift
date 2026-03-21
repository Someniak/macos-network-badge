// ---------------------------------------------------------
// LatencyMonitor.swift — Measures internet latency (ping)
//
// This monitor periodically sends a tiny HTTP request to
// Apple's captive portal server and measures how long the
// response takes. This gives us real-world latency that
// reflects what you'd actually experience browsing.
//
// Why HTTP instead of ICMP ping?
//   1. Works through captive portals (train WiFi login pages)
//   2. No special permissions needed (ICMP requires root)
//   3. Tests actual internet connectivity, not just local network
//   4. Apple's server is globally distributed and very reliable
// ---------------------------------------------------------

import Foundation
import Combine

/// Periodically measures internet latency and publishes results.
///
/// Usage:
///   let monitor = LatencyMonitor()
///   monitor.start()   // begins measuring every 3 seconds
///   // read monitor.currentLatencyMs, monitor.quality, etc.
///   monitor.stop()    // stop measuring
///
final class LatencyMonitor: ObservableObject {

    // MARK: - Published Properties (the UI reads these)

    /// Most recent latency in milliseconds (nil if no measurement yet)
    @Published var currentLatencyMs: Double? = nil

    /// Rolling average of recent measurements
    @Published var averageLatencyMs: Double? = nil

    /// Human-friendly quality rating based on current latency
    @Published var quality: LatencyQuality = .unknown

    /// The quality level before the most recent change
    /// (used by NotificationManager to detect degradation)
    @Published var previousQuality: LatencyQuality = .unknown

    /// History of recent measurements (newest first, max 20)
    @Published var samples: [LatencySample] = []

    /// Whether a measurement is currently in progress
    @Published var isMeasuring: Bool = false

    /// Packet loss as a percentage (0-100) over the sample window.
    /// Computed from the ratio of failed samples to total samples.
    var packetLossPercent: Double {
        guard !samples.isEmpty else { return 0.0 }
        let failedCount = samples.filter { !$0.wasSuccessful }.count
        return (Double(failedCount) / Double(samples.count)) * 100.0
    }

    /// Jitter in milliseconds — the average absolute difference between
    /// consecutive successful latency measurements. High jitter means
    /// unstable connection (bad for video calls even if avg latency is OK).
    var jitterMs: Double? {
        let successful = samples.reversed().filter { $0.wasSuccessful }
        guard successful.count >= 2 else { return nil }

        var totalDiff = 0.0
        for i in 1..<successful.count {
            totalDiff += abs(successful[i].latencyMs - successful[i - 1].latencyMs)
        }
        return totalDiff / Double(successful.count - 1)
    }

    /// Combined quality score from 0 (worst) to 100 (best).
    /// Blends latency, packet loss, and jitter into one glanceable number.
    var qualityScore: Int? {
        guard !samples.isEmpty else { return nil }

        // Latency component (0-100): 0ms→100, 300ms+→0
        let latencyScore: Double
        if let avg = averageLatencyMs {
            latencyScore = max(0, 100.0 - (avg / 3.0))
        } else {
            latencyScore = 0  // all timeouts
        }

        // Packet loss component (0-100): 0%→100, 100%→0
        let lossScore = 100.0 - packetLossPercent

        // Jitter component (0-100): 0ms→100, 100ms+→0
        let jitterScore: Double
        if let jitter = jitterMs {
            jitterScore = max(0, 100.0 - jitter)
        } else {
            jitterScore = latencyScore > 0 ? 100.0 : 0  // no jitter data = follow latency
        }

        // Weighted blend: latency 50%, loss 30%, jitter 20%
        let score = latencyScore * 0.5 + lossScore * 0.3 + jitterScore * 0.2
        return max(0, min(100, Int(score.rounded())))
    }

    // MARK: - Configuration

    /// How often to measure latency (in seconds), persisted across launches
    @Published var measurementInterval: TimeInterval = 3.0 {
        didSet {
            UserDefaults.standard.set(measurementInterval, forKey: "pollInterval")
            restartTimer()
        }
    }

    /// The URL we ping to measure latency, persisted across launches
    @Published var targetURL: URL = URL(string: "http://captive.apple.com/hotspot-detect.html")! {
        didSet {
            UserDefaults.standard.set(targetURL.absoluteString, forKey: "pollTarget")
        }
    }

    /// How long to wait before declaring a timeout (in seconds)
    let timeoutInterval: TimeInterval

    /// How many samples to keep in history
    let maxSampleCount: Int

    // MARK: - Private Properties

    /// Timer that triggers periodic measurements
    private var timer: Timer? = nil

    /// URLSession configured for latency measurement
    /// (short timeout, no caching, no cookies)
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral  // no caching
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // MARK: - Initialization

    /// Creates a new LatencyMonitor.
    ///
    /// - Parameters:
    ///   - interval: Seconds between measurements (default: 3)
    ///   - timeout: Seconds before a request is considered timed out (default: 10)
    ///   - maxSamples: How many historical samples to keep (default: 20)
    init(
        timeout: TimeInterval = 10.0,
        maxSamples: Int = 20
    ) {
        self.timeoutInterval = timeout
        self.maxSampleCount = maxSamples
        let savedInterval = UserDefaults.standard.double(forKey: "pollInterval")
        if savedInterval > 0 { self.measurementInterval = savedInterval }
        if let saved = UserDefaults.standard.string(forKey: "pollTarget"),
           let url = URL(string: saved) {
            self.targetURL = url
        }
    }

    // MARK: - Start / Stop

    /// Begin periodic latency measurements.
    /// Call this when the app launches.
    func start() {
        // Do an initial measurement right away
        measureLatency()

        // Then schedule periodic measurements
        timer = Timer.scheduledTimer(
            withTimeInterval: measurementInterval,
            repeats: true
        ) { [weak self] _ in
            self?.measureLatency()
        }
    }

    /// Stop measuring. Call this when the app quits.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Restarts the periodic timer with the current interval.
    private func restartTimer() {
        guard timer != nil else { return }  // not started yet
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: measurementInterval,
            repeats: true
        ) { [weak self] _ in
            self?.measureLatency()
        }
    }

    // MARK: - Measurement

    /// Performs a single latency measurement.
    ///
    /// How it works:
    ///   1. Record the current time
    ///   2. Send a tiny HTTP GET request to Apple's server
    ///   3. When the response arrives, calculate elapsed time
    ///   4. Store the result and update published properties
    func measureLatency() {
        // Don't stack up measurements if one is already in progress
        guard !isMeasuring else { return }
        isMeasuring = true

        // Record the start time with high precision
        let startTime = CFAbsoluteTimeGetCurrent()

        // Create a simple GET request
        var request = URLRequest(url: targetURL)
        request.httpMethod = "GET"
        // Add a cache-busting query parameter so proxies don't cache it
        request.url = URL(string: "\(targetURL.absoluteString)?t=\(startTime)")

        // Send the request and measure response time
        let task = session.dataTask(with: request) { [weak self] _, response, error in
            // Calculate how long the request took
            let endTime = CFAbsoluteTimeGetCurrent()
            let latencyMs = (endTime - startTime) * 1000.0  // convert to milliseconds

            // Check if the request succeeded
            let httpResponse = response as? HTTPURLResponse
            let wasSuccessful = (error == nil) && (httpResponse?.statusCode ?? 0) < 400

            // Create a sample record
            let sample = LatencySample(
                timestamp: Date(),
                latencyMs: wasSuccessful ? latencyMs : 0,
                wasSuccessful: wasSuccessful
            )

            // Update published properties on the main thread
            // (SwiftUI requires this)
            DispatchQueue.main.async {
                self?.recordSample(sample)
                self?.isMeasuring = false
            }
        }

        task.resume()
    }

    // MARK: - Sample Management

    /// Records a new measurement and recalculates averages.
    ///
    /// - Parameter sample: The measurement to record
    func recordSample(_ sample: LatencySample) {
        // Add to the front of the list (newest first)
        samples.insert(sample, at: 0)

        // Trim to max size (remove oldest)
        if samples.count > maxSampleCount {
            samples = Array(samples.prefix(maxSampleCount))
        }

        // Save previous quality before updating (for change detection)
        previousQuality = quality

        // Update current latency
        if sample.wasSuccessful {
            currentLatencyMs = sample.latencyMs
            quality = LatencyQuality.from(latencyMs: sample.latencyMs)
        } else {
            currentLatencyMs = nil
            quality = .bad
        }

        // Recalculate rolling average (only from successful samples)
        recalculateAverage()
    }

    /// Recalculates the average latency from successful samples.
    private func recalculateAverage() {
        let successfulSamples = samples.filter { $0.wasSuccessful }

        guard !successfulSamples.isEmpty else {
            averageLatencyMs = nil
            return
        }

        let totalMs = successfulSamples.reduce(0.0) { $0 + $1.latencyMs }
        averageLatencyMs = totalMs / Double(successfulSamples.count)
    }
}
