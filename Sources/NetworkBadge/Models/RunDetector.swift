// ---------------------------------------------------------
// RunDetector.swift — Group records into independent journeys
//
// Detects "runs" (train rides, café sessions, walks) by
// splitting on time gaps > 5 minutes between consecutive
// records. Single-pass O(n) algorithm, no schema changes.
// ---------------------------------------------------------

import Foundation

// MARK: - Run

/// A contiguous group of records with no gap > maxGapSeconds.
struct Run: Identifiable {
    /// 1-based run number
    let id: Int
    let startTime: Date
    let endTime: Date
    let recordCount: Int
    /// O(1) lookup for record membership
    let recordIDs: Set<UUID>
}

// MARK: - Run Detector

struct RunDetector {

    /// Maximum time gap (seconds) between consecutive records
    /// before starting a new run. Shared with QualityTrailBuilder.
    static let maxGapSeconds: TimeInterval = 300  // 5 minutes

    /// Minimum number of records for a run to be considered real.
    /// Smaller groups are noise, not journeys.
    static let minRecordsPerRun: Int = 10

    /// Minimum fraction of records that must have speed > 0 for
    /// the run to count as actual movement (not a stationary session).
    static let minMovingFraction: Double = 0.2

    /// Speed threshold in km/h — records at or above this are "moving".
    static let movingSpeedThreshold: Double = 3.0

    /// Detect runs from a list of records by sorting ascending
    /// by timestamp and splitting on gaps > maxGapSeconds.
    static func detectRuns(from records: [QualityRecord]) -> [Run] {
        let sorted = records.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first else { return [] }

        var runs: [Run] = []
        var runStart = first.timestamp
        var runIDs: Set<UUID> = [first.id]

        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            let gap = curr.timestamp.timeIntervalSince(prev.timestamp)

            if gap > maxGapSeconds {
                // Close current run
                runs.append(Run(
                    id: runs.count + 1,
                    startTime: runStart,
                    endTime: prev.timestamp,
                    recordCount: runIDs.count,
                    recordIDs: runIDs
                ))
                // Start new run
                runStart = curr.timestamp
                runIDs = [curr.id]
            } else {
                runIDs.insert(curr.id)
            }
        }

        // Close final run
        runs.append(Run(
            id: runs.count + 1,
            startTime: runStart,
            endTime: sorted.last!.timestamp,
            recordCount: runIDs.count,
            recordIDs: runIDs
        ))

        // Filter out tiny runs and stationary sessions
        let meaningful = runs.filter { run in
            guard run.recordCount >= minRecordsPerRun else { return false }
            return hasRealMovement(run: run, sortedRecords: sorted)
        }

        // Re-number so IDs are contiguous
        let renumbered = meaningful.enumerated().map { i, run in
            Run(id: i + 1, startTime: run.startTime, endTime: run.endTime,
                recordCount: run.recordCount, recordIDs: run.recordIDs)
        }

        return renumbered.reversed()
    }

    /// Check whether a run contains real movement, not just stationary polling.
    /// Uses speedKmh when available; falls back to geographic displacement
    /// for older records that lack speed data.
    private static func hasRealMovement(run: Run, sortedRecords: [QualityRecord]) -> Bool {
        let runRecords = sortedRecords.filter { run.recordIDs.contains($0.id) }

        // Primary check: fraction of records with speed above threshold
        let withSpeed = runRecords.filter { $0.speedKmh != nil }
        if !withSpeed.isEmpty {
            let moving = withSpeed.filter { ($0.speedKmh ?? 0) >= movingSpeedThreshold }
            return Double(moving.count) / Double(withSpeed.count) >= minMovingFraction
        }

        // Fallback for legacy records without speed: check geographic spread.
        // If the bounding box of valid coordinates spans > 100m in any direction,
        // there was real movement.
        let located = runRecords.filter {
            $0.latitude != 0 && $0.longitude != 0
        }
        guard located.count >= 2 else { return false }

        let lats = located.map { $0.latitude }
        let lons = located.map { $0.longitude }
        let latSpan = (lats.max()! - lats.min()!) * 111_000  // degrees → meters
        let lonSpan = (lons.max()! - lons.min()!) * 111_000 * cos(lats.first! * .pi / 180)

        return max(latSpan, lonSpan) > 100
    }
}
