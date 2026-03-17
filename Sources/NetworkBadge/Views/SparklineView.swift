// ---------------------------------------------------------
// SparklineView.swift — Mini line chart for latency history
//
// Draws a sparkline graph showing recent latency measurements.
// Green at the bottom (low latency = good), red at the top
// (high latency = bad). Failed samples appear as red dots.
// ---------------------------------------------------------

import SwiftUI

/// A mini line chart that visualizes recent latency samples.
///
/// Usage:
///   SparklineView(samples: latencyMonitor.samples)
///       .frame(height: 60)
///
struct SparklineView: View {

    /// The latency samples to display (newest first)
    let samples: [LatencySample]

    /// Reference line threshold in ms (the "good" boundary)
    let referenceLineMs: Double = 80.0

    var body: some View {
        if successfulSamples.count < 2 {
            // Not enough data — show placeholder
            emptyState
        } else {
            // Draw the sparkline chart
            chartView
        }
    }

    // MARK: - Data Helpers

    /// Only successful samples can be plotted as line points
    private var successfulSamples: [LatencySample] {
        samples.filter { $0.wasSuccessful }
    }

    /// Samples in chronological order (oldest first) for left-to-right drawing
    private var chronologicalSamples: [LatencySample] {
        Array(successfulSamples.reversed())
    }

    /// Min/max for Y-axis scaling, with padding
    private var yMin: Double {
        max(0, (chronologicalSamples.map(\.latencyMs).min() ?? 0) * 0.8)
    }

    private var yMax: Double {
        let maxVal = chronologicalSamples.map(\.latencyMs).max() ?? 100
        // Ensure we show at least up to the reference line
        return max(maxVal * 1.1, referenceLineMs * 1.3)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack {
            Spacer()
            Text("Waiting for data…")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Chart

    private var chartView: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack(alignment: .topLeading) {
                // Fill under the line
                SparklineFill(
                    dataPoints: chronologicalSamples.map(\.latencyMs),
                    yMin: yMin,
                    yMax: yMax
                )
                .fill(
                    LinearGradient(
                        colors: [Color.green.opacity(0.15), Color.red.opacity(0.15)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )

                // The line itself
                SparklinePath(
                    dataPoints: chronologicalSamples.map(\.latencyMs),
                    yMin: yMin,
                    yMax: yMax
                )
                .stroke(
                    LinearGradient(
                        colors: [.green, .yellow, .red],
                        startPoint: .bottom,
                        endPoint: .top
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

                // Reference line at "good" threshold (80ms)
                let refY = yPosition(for: referenceLineMs, in: height)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: refY))
                    path.addLine(to: CGPoint(x: width, y: refY))
                }
                .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                // Failed samples shown as red dots at corresponding X positions
                ForEach(failedSamplePositions(width: width), id: \.x) { point in
                    Circle()
                        .fill(Color.red)
                        .frame(width: 5, height: 5)
                        .position(x: point.x, y: height / 2)
                }

                // Y-axis labels: min and max
                VStack {
                    Text("\(Int(yMax))ms")
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                    Text("\(Int(yMin))ms")
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
        }
    }

    // MARK: - Helpers

    /// Convert a latency value to a Y coordinate
    private func yPosition(for latencyMs: Double, in height: CGFloat) -> CGFloat {
        let range = yMax - yMin
        guard range > 0 else { return height / 2 }
        let normalized = (latencyMs - yMin) / range
        // Invert: low latency = bottom of chart, high = top
        return CGFloat(1.0 - normalized) * height
    }

    /// X positions for failed samples (based on their index in the full samples array)
    private func failedSamplePositions(width: CGFloat) -> [CGPoint] {
        let allChronological = Array(samples.reversed())
        let count = allChronological.count
        guard count > 1 else { return [] }

        return allChronological.enumerated().compactMap { index, sample in
            guard !sample.wasSuccessful else { return nil }
            let x = CGFloat(index) / CGFloat(count - 1) * width
            return CGPoint(x: x, y: 0)
        }
    }
}

// MARK: - Sparkline Path Shape

/// Draws the sparkline as a connected line path.
struct SparklinePath: Shape {
    let dataPoints: [Double]
    let yMin: Double
    let yMax: Double

    func path(in rect: CGRect) -> Path {
        guard dataPoints.count >= 2 else { return Path() }

        var path = Path()
        let stepX = rect.width / CGFloat(dataPoints.count - 1)

        for (index, value) in dataPoints.enumerated() {
            let x = CGFloat(index) * stepX
            let y = yPosition(for: value, in: rect.height)

            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }

    private func yPosition(for value: Double, in height: CGFloat) -> CGFloat {
        let range = yMax - yMin
        guard range > 0 else { return height / 2 }
        let normalized = (value - yMin) / range
        return CGFloat(1.0 - normalized) * height
    }
}

// MARK: - Sparkline Fill Shape

/// Draws the filled area under the sparkline.
struct SparklineFill: Shape {
    let dataPoints: [Double]
    let yMin: Double
    let yMax: Double

    func path(in rect: CGRect) -> Path {
        guard dataPoints.count >= 2 else { return Path() }

        var path = Path()
        let stepX = rect.width / CGFloat(dataPoints.count - 1)

        // Start at bottom-left
        path.move(to: CGPoint(x: 0, y: rect.height))

        // Draw line points
        for (index, value) in dataPoints.enumerated() {
            let x = CGFloat(index) * stepX
            let y = yPosition(for: value, in: rect.height)
            path.addLine(to: CGPoint(x: x, y: y))
        }

        // Close back to bottom-right, then bottom-left
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()

        return path
    }

    private func yPosition(for value: Double, in height: CGFloat) -> CGFloat {
        let range = yMax - yMin
        guard range > 0 else { return height / 2 }
        let normalized = (value - yMin) / range
        return CGFloat(1.0 - normalized) * height
    }
}
