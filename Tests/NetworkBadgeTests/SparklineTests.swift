// ---------------------------------------------------------
// SparklineTests.swift — Tests for the SparklinePath shape
//
// Tests the sparkline chart rendering logic:
//   - Y-axis scaling with known data points
//   - Empty and single-sample edge cases
//   - Path generation for the line and fill shapes
// ---------------------------------------------------------

import SwiftUI
import XCTest
@testable import NetworkBadge

final class SparklineTests: XCTestCase {

    // MARK: - SparklinePath Tests

    /// SparklinePath with valid data should produce a non-empty path
    func testSparklinePathWithData() {
        let shape = SparklinePath(
            dataPoints: [50.0, 100.0, 75.0],
            yMin: 0,
            yMax: 200
        )

        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = shape.path(in: rect)

        // Path should not be empty when we have data points
        XCTAssertFalse(path.isEmpty)
    }

    /// SparklinePath with fewer than 2 points should be empty
    func testSparklinePathWithSinglePoint() {
        let shape = SparklinePath(
            dataPoints: [50.0],
            yMin: 0,
            yMax: 100
        )

        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = shape.path(in: rect)

        XCTAssertTrue(path.isEmpty)
    }

    /// SparklinePath with no data should be empty
    func testSparklinePathEmpty() {
        let shape = SparklinePath(
            dataPoints: [],
            yMin: 0,
            yMax: 100
        )

        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = shape.path(in: rect)

        XCTAssertTrue(path.isEmpty)
    }

    // MARK: - SparklineFill Tests

    /// SparklineFill with valid data should produce a non-empty path
    func testSparklineFillWithData() {
        let shape = SparklineFill(
            dataPoints: [50.0, 100.0, 75.0],
            yMin: 0,
            yMax: 200
        )

        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = shape.path(in: rect)

        XCTAssertFalse(path.isEmpty)
    }

    /// SparklineFill with fewer than 2 points should be empty
    func testSparklineFillWithSinglePoint() {
        let shape = SparklineFill(
            dataPoints: [50.0],
            yMin: 0,
            yMax: 100
        )

        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = shape.path(in: rect)

        XCTAssertTrue(path.isEmpty)
    }

    // MARK: - Y-Axis Scaling Tests

    /// Path should correctly scale data within the given Y range
    func testYAxisScaling() {
        // Data at yMin should be at the bottom (y = height)
        // Data at yMax should be at the top (y = 0)
        let shape = SparklinePath(
            dataPoints: [0.0, 100.0],
            yMin: 0,
            yMax: 100
        )

        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = shape.path(in: rect)

        // Path should exist and span the full height
        XCTAssertFalse(path.isEmpty)
        let bounds = path.boundingRect
        // First point at yMin=0 should be at y=100 (bottom)
        // Second point at yMax=100 should be at y=0 (top)
        XCTAssertEqual(bounds.minY, 0, accuracy: 0.1)
        XCTAssertEqual(bounds.maxY, 100, accuracy: 0.1)
    }

    /// Equal yMin and yMax should not crash (degenerate range)
    func testDegenerateYRange() {
        let shape = SparklinePath(
            dataPoints: [50.0, 50.0],
            yMin: 50,
            yMax: 50
        )

        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        // Should not crash — falls back to height/2
        let path = shape.path(in: rect)
        XCTAssertFalse(path.isEmpty)
    }
}
