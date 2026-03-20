// ---------------------------------------------------------
// QualityTrailRenderer.swift — Smooth gradient quality trail
//
// Draws a continuous colored polyline trail showing the travel
// path, with color smoothly transitioning by network quality:
//   Green → Yellow → Orange → Red
//
// Uses a layered approach: one continuous base polyline (green) per
// trip with colored overlays for degraded sections on top.
// ---------------------------------------------------------

import MapKit
import SwiftUI

// MARK: - Trail Segment

/// A single segment of the quality trail between two consecutive measurements.
struct TrailSegment {
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let quality: LatencyQuality
    let latencyMs: Double
    let wasSuccessful: Bool
    let locationSource: LocationSource
    let speedKmh: Double
}

// MARK: - Trail Builder

/// Builds trail segments from quality records.
struct QualityTrailBuilder {

    /// Maximum time gap (seconds) between records before splitting the trail.
    static let maxGapSeconds: TimeInterval = RunDetector.maxGapSeconds

    /// Convert sorted records into colored polyline segments.
    static func buildTrail(from records: [QualityRecord]) -> [TrailSegment] {
        let located = records
            .filter { $0.latitude != 0 && $0.longitude != 0 }
            .sorted { $0.timestamp < $1.timestamp }

        guard located.count >= 2 else { return [] }

        var segments: [TrailSegment] = []
        for i in 0..<(located.count - 1) {
            let current = located[i]
            let next = located[i + 1]

            let gap = next.timestamp.timeIntervalSince(current.timestamp)
            guard gap < maxGapSeconds else { continue }

            let distanceM = CLLocation(latitude: current.latitude, longitude: current.longitude)
                .distance(from: CLLocation(latitude: next.latitude, longitude: next.longitude))
            let speedKmh = gap > 0 ? (distanceM / gap) * 3.6 : 0

            // Skip physically impossible jumps (prevents spider-web pattern
            // when CoreLocation WiFi + GPS2IP both recorded nearby positions)
            guard speedKmh < 400 else { continue }

            // Use the worse quality of the two endpoints so the segment
            // accurately represents the quality across its span
            let segmentQuality = worse(current.qualityLevel, next.qualityLevel)

            segments.append(TrailSegment(
                start: CLLocationCoordinate2D(latitude: current.latitude, longitude: current.longitude),
                end: CLLocationCoordinate2D(latitude: next.latitude, longitude: next.longitude),
                quality: segmentQuality,
                latencyMs: current.latencyMs,
                wasSuccessful: current.wasSuccessful,
                locationSource: LocationSource(rawValue: current.locationSource) ?? .coreLocation,
                speedKmh: speedKmh
            ))
        }
        return segments
    }

    /// Returns the worse (higher latency) of two quality levels.
    private static func worse(_ a: LatencyQuality, _ b: LatencyQuality) -> LatencyQuality {
        let order: [LatencyQuality] = [.excellent, .good, .fair, .poor, .bad, .unknown]
        let ai = order.firstIndex(of: a) ?? order.count
        let bi = order.firstIndex(of: b) ?? order.count
        return ai >= bi ? a : b
    }
}

// MARK: - Quality Polyline

/// Polyline segment carrying its computed color for the renderer.
final class QualityPolyline: MKPolyline {
    var color: NSColor = .systemGreen
    var isBase: Bool = false
}

// MARK: - Live Trail Polyline

/// Dashed polyline from the last recorded point to the current live position.
final class LiveTrailPolyline: MKPolyline {
    var quality: LatencyQuality = .unknown
}

// MARK: - Trail Map View (NSViewRepresentable)

/// An MKMapView wrapper that renders a smooth gradient quality trail
/// and a live pulsing position marker.
struct TrailMapView: NSViewRepresentable {
    let records: [QualityRecord]
    let segments: [TrailSegment]
    let currentLatitude: Double?
    let currentLongitude: Double?
    let currentBearing: Double
    @Binding var region: MKCoordinateRegion
    @Binding var selectedRecord: QualityRecord?
    /// Incremented when a button programmatically changes the region
    var regionToken: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.setRegion(region, animated: false)
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        let newRecordIDs = records.map { $0.id }
        let newSegmentCount = segments.count
        let newLivePosition: CLLocationCoordinate2D? = currentLatitude.flatMap { lat in
            currentLongitude.map { lon in CLLocationCoordinate2D(latitude: lat, longitude: lon) }
        }

        // Detect programmatic region change (e.g. "center on user" button)
        if regionToken != coordinator.lastRegionToken {
            coordinator.lastRegionToken = regionToken
            mapView.setRegion(region, animated: true)
        }

        let trailChanged = newRecordIDs != coordinator.lastRecordIDs
            || newSegmentCount != coordinator.lastSegmentCount
        let positionChanged = newLivePosition?.latitude != coordinator.lastLivePosition?.latitude
            || newLivePosition?.longitude != coordinator.lastLivePosition?.longitude
            || currentBearing != coordinator.lastBearing

        guard trailChanged || positionChanged else { return }

        coordinator.lastRecordIDs = newRecordIDs
        coordinator.lastSegmentCount = newSegmentCount
        coordinator.lastLivePosition = newLivePosition
        coordinator.lastBearing = currentBearing

        if trailChanged {
            mapView.removeOverlays(mapView.overlays)
            coordinator.liveTrailOverlay = nil

            // Build smoothed polylines grouped into continuous trips
            coordinator.lastSmoothedCoord = nil
            for trip in groupIntoTrips(segments) {
                let polylines = buildSmoothedPolylines(from: trip)
                for polyline in polylines {
                    mapView.addOverlay(polyline)
                }
                // Track the last smoothed coordinate from the base polyline
                if let base = polylines.first, base.pointCount > 0 {
                    let points = base.points()
                    coordinator.lastSmoothedCoord = points[base.pointCount - 1].coordinate
                }
            }
        }

        // Update live position marker
        if let position = newLivePosition {
            if let existing = coordinator.liveAnnotation {
                existing.coordinate = position
                existing.bearing = currentBearing
                if let view = mapView.view(for: existing) {
                    let hostingView = NSHostingView(rootView: LivePositionMarker(bearing: currentBearing))
                    hostingView.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
                    view.subviews.forEach { $0.removeFromSuperview() }
                    view.addSubview(hostingView)
                    view.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
                }
            } else {
                let live = LivePositionAnnotation()
                live.coordinate = position
                live.bearing = currentBearing
                mapView.addAnnotation(live)
                coordinator.liveAnnotation = live
            }
        } else if let existing = coordinator.liveAnnotation {
            mapView.removeAnnotation(existing)
            coordinator.liveAnnotation = nil
        }

        // Live trail: dashed segment from last smoothed point → current position
        let trailEnd = coordinator.lastSmoothedCoord ?? segments.last?.end
        if let position = newLivePosition, let anchor = trailEnd {
            if let old = coordinator.liveTrailOverlay {
                mapView.removeOverlay(old)
            }
            var coords = [anchor, position]
            let liveLine = LiveTrailPolyline(coordinates: &coords, count: 2)
            liveLine.quality = segments.last?.quality ?? .unknown
            mapView.addOverlay(liveLine)
            coordinator.liveTrailOverlay = liveLine
        } else if let old = coordinator.liveTrailOverlay {
            mapView.removeOverlay(old)
            coordinator.liveTrailOverlay = nil
        }
    }

    // MARK: - Trip Grouping

    /// Group consecutive segments into trips. A new trip starts when
    /// the gap between consecutive segments exceeds 5 km (must be large
    /// enough to tolerate segments skipped by the speed filter during
    /// fast train travel — at 200 km/h a single skipped 10s interval
    /// creates a ~1 km gap).
    private func groupIntoTrips(_ segments: [TrailSegment]) -> [[TrailSegment]] {
        guard !segments.isEmpty else { return [] }
        var trips: [[TrailSegment]] = [[segments[0]]]
        for i in 1..<segments.count {
            let prev = segments[i - 1]
            let curr = segments[i]
            let gap = CLLocation(latitude: prev.end.latitude, longitude: prev.end.longitude)
                .distance(from: CLLocation(latitude: curr.start.latitude, longitude: curr.start.longitude))
            if gap < 5000 {
                trips[trips.count - 1].append(curr)
            } else {
                trips.append([curr])
            }
        }
        return trips
    }

    // MARK: - Gradient Polyline Builder

    /// Build a base polyline (full trip path, green) plus overlay
    /// polylines for non-green sections. The base guarantees one
    /// continuous line with zero gaps; overlays add color variation.
    private func buildSmoothedPolylines(from trip: [TrailSegment]) -> [QualityPolyline] {
        guard !trip.isEmpty else { return [] }

        // 1. Collect ALL coordinates, speeds, and segment→coord index mapping
        var allCoords: [CLLocationCoordinate2D] = []
        var coordSpeeds: [Double] = []
        // segStartIdx[i] = index in allCoords where segment i starts
        // segEndIdx[i]   = index in allCoords where segment i ends
        var segStartIdx: [Int] = []
        var segEndIdx: [Int] = []
        for segment in trip {
            if allCoords.isEmpty
                || allCoords.last!.latitude != segment.start.latitude
                || allCoords.last!.longitude != segment.start.longitude {
                allCoords.append(segment.start)
                coordSpeeds.append(segment.speedKmh)
            }
            segStartIdx.append(allCoords.count - 1)
            allCoords.append(segment.end)
            coordSpeeds.append(segment.speedKmh)
            segEndIdx.append(allCoords.count - 1)
        }

        // 2. Smooth GPS jitter (adaptive window based on speed)
        allCoords = smoothCoordinates(allCoords, speeds: coordSpeeds)

        // 3. Base polyline — full path, green (rendered below everything)
        let base = QualityPolyline(coordinates: &allCoords, count: allCoords.count)
        base.color = scoreToColor(0) // green
        base.isBase = true
        var result: [QualityPolyline] = [base]

        // 4. Compute smoothed quality scores
        let rawScores = trip.map { segment -> Double in
            segment.wasSuccessful ? latencyToScore(segment.latencyMs) : 2.5
        }
        let window = 7
        var smoothed: [Double] = []
        for i in 0..<rawScores.count {
            let lo = max(0, i - window / 2)
            let hi = min(rawScores.count, i + window / 2 + 1)
            smoothed.append(rawScores[lo..<hi].reduce(0, +) / Double(hi - lo))
        }

        // 5. Quantize and build overlay polylines for non-green runs
        //    using smoothed coordinates from allCoords via the index mapping
        let quantized = smoothed.map { Int(($0 * 2).rounded()) }
        var runStart = 0

        for i in 0...trip.count {
            let isEnd = i == trip.count
            let bandChanged = isEnd || quantized[i] != quantized[runStart]

            if bandChanged {
                if quantized[runStart] > 1 {
                    let coordLo = segStartIdx[runStart]
                    let coordHi = segEndIdx[i - 1]
                    let count = coordHi - coordLo + 1
                    if count >= 2 {
                        var coords = Array(allCoords[coordLo...coordHi])
                        let overlay = QualityPolyline(coordinates: &coords, count: coords.count)
                        overlay.color = scoreToColor(smoothed[(runStart + i - 1) / 2])
                        overlay.isBase = false
                        result.append(overlay)
                    }
                }
                if !isEnd { runStart = i }
            }
        }

        return result
    }

    // MARK: - Coordinate Smoothing

    /// Smooth GPS jitter using two passes of a moving-average filter.
    /// Preserves first and last points exactly. Window size adapts
    /// to speed — faster travel gets more smoothing.
    private func smoothCoordinates(_ coords: [CLLocationCoordinate2D],
                                   speeds: [Double] = []) -> [CLLocationCoordinate2D] {
        guard coords.count >= 3 else { return coords }

        // Determine per-point window size based on speed
        let windows: [Int] = (0..<coords.count).map { i in
            let speed = (i < speeds.count) ? speeds[i] : 0
            switch speed {
            case 80...:   return 9   // fast train
            case 40...:   return 5   // car / slow train
            case 5...:    return 3   // walking / station approach — light smoothing
            default:      return 1   // stationary — no smoothing
            }
        }

        // Two-pass smoothing for a cleaner result
        var current = coords
        for _ in 0..<2 {
            var next = current
            for i in 1..<(current.count - 1) {
                let w = windows[i]
                guard w > 1 else { continue }
                let half = w / 2
                let lo = max(0, i - half)
                let hi = min(current.count - 1, i + half)
                let count = Double(hi - lo + 1)
                var avgLat = 0.0
                var avgLon = 0.0
                for j in lo...hi {
                    avgLat += current[j].latitude
                    avgLon += current[j].longitude
                }
                next[i] = CLLocationCoordinate2D(latitude: avgLat / count,
                                                  longitude: avgLon / count)
            }
            current = next
        }
        return current
    }

    // MARK: - Color Mapping

    /// Map latency (ms) to a continuous quality score: 0.0 (excellent) → 4.0 (bad).
    private func latencyToScore(_ ms: Double) -> Double {
        switch ms {
        case ..<30:  return 0.0
        case ..<80:  return 0.0 + (ms - 30) / 50         // 0.0 → 1.0
        case ..<150: return 1.0 + (ms - 80) / 70         // 1.0 → 2.0
        case ..<300: return 2.0 + (ms - 150) / 150       // 2.0 → 3.0
        default:     return min(4.0, 3.0 + (ms - 300) / 200) // 3.0 → 4.0
        }
    }

    /// Map a quality score to a smooth NSColor gradient.
    /// 0=green, 1=green→yellow, 2=yellow→orange, 3=orange→red, 4=red
    private func scoreToColor(_ score: Double) -> NSColor {
        switch score {
        case ..<1:
            return interpolateColor(from: .systemGreen, to: .systemGreen, t: score)
        case 1..<2:
            return interpolateColor(from: .systemGreen, to: .systemYellow, t: score - 1)
        case 2..<3:
            return interpolateColor(from: .systemYellow, to: .systemOrange, t: score - 2)
        case 3..<4:
            return interpolateColor(from: .systemOrange, to: .systemRed, t: score - 3)
        default:
            return .systemRed
        }
    }

    private func interpolateColor(from: NSColor, to: NSColor, t: Double) -> NSColor {
        let t = max(0, min(1, t))
        guard let f = from.usingColorSpace(.sRGB),
              let tt = to.usingColorSpace(.sRGB) else { return from }
        return NSColor(
            red: f.redComponent + (tt.redComponent - f.redComponent) * t,
            green: f.greenComponent + (tt.greenComponent - f.greenComponent) * t,
            blue: f.blueComponent + (tt.blueComponent - f.blueComponent) * t,
            alpha: 0.85
        )
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: TrailMapView

        var lastRecordIDs: [UUID] = []
        var lastSegmentCount: Int = -1
        var lastLivePosition: CLLocationCoordinate2D? = nil
        var lastBearing: Double = .nan

        var liveAnnotation: LivePositionAnnotation? = nil
        var liveTrailOverlay: LiveTrailPolyline? = nil
        /// Last coordinate of the smoothed trail (for live trail connection)
        var lastSmoothedCoord: CLLocationCoordinate2D? = nil
        /// Token to detect programmatic region changes from buttons
        var lastRegionToken: Int = 0

        init(parent: TrailMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let liveLine = overlay as? LiveTrailPolyline {
                let renderer = MKPolylineRenderer(polyline: liveLine)
                renderer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.4)
                renderer.lineWidth = 4
                renderer.lineDashPattern = [8, 6]
                renderer.lineCap = .round
                return renderer
            }
            if let polyline = overlay as? QualityPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = polyline.color
                renderer.lineWidth = 5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let liveAnnotation = annotation as? LivePositionAnnotation {
                return livePositionView(for: liveAnnotation, in: mapView)
            }
            return nil
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            DispatchQueue.main.async {
                self.parent.region = mapView.region
            }
        }

        // MARK: - View Builders

        private func livePositionView(
            for annotation: LivePositionAnnotation,
            in mapView: MKMapView
        ) -> MKAnnotationView {
            let id = "LivePosition"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation

            let marker = LivePositionMarker(bearing: annotation.bearing)
            let hostingView = NSHostingView(rootView: marker)
            hostingView.frame = CGRect(x: 0, y: 0, width: 44, height: 44)

            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(hostingView)
            view.frame = hostingView.frame
            view.centerOffset = CGPoint(x: 0, y: 0)

            return view
        }
    }
}

// MARK: - Annotation Types

/// Annotation for the live pulsing position marker.
final class LivePositionAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate = CLLocationCoordinate2D()
    var bearing: Double = 0
}

// MARK: - Live Position Marker (SwiftUI)

/// Uber-style pulsing blue dot with bearing arrow.
struct LivePositionMarker: View {
    let bearing: Double

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: isPulsing ? 40 : 24, height: isPulsing ? 40 : 24)
                .animation(
                    .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            Circle()
                .fill(Color.blue)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))

            Image(systemName: "location.north.fill")
                .font(.system(size: 10))
                .foregroundColor(.blue)
                .rotationEffect(.degrees(bearing))
                .offset(y: -18)
        }
        .onAppear { isPulsing = true }
    }
}
