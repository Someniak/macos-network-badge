// ---------------------------------------------------------
// QualityTrailRenderer.swift — Uber-style quality trail on map
//
// Draws a colored polyline trail showing the travel path,
// with each segment colored by network quality. Uses
// MKMapView via NSViewRepresentable for proper polyline
// rendering with variable colors per segment.
//
// Also includes the live pulsing position marker with
// bearing arrow (like Uber's driver marker).
// ---------------------------------------------------------

import MapKit
import SwiftUI

// MARK: - Trail Segment

/// A single segment of the quality trail between two consecutive measurements.
struct TrailSegment {
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let quality: LatencyQuality
    let locationSource: LocationSource
}

// MARK: - Trail Builder

/// Builds trail segments from quality records.
struct QualityTrailBuilder {

    /// Maximum time gap (seconds) between records before splitting the trail.
    /// Gaps larger than this are treated as separate trips.
    static let maxGapSeconds: TimeInterval = 600  // 10 minutes

    /// Convert sorted records into colored polyline segments.
    static func buildTrail(from records: [QualityRecord]) -> [TrailSegment] {
        // Filter out records with no location, then sort by time
        let located = records
            .filter { $0.latitude != 0 && $0.longitude != 0 }
            .sorted { $0.timestamp < $1.timestamp }

        guard located.count >= 2 else { return [] }

        var segments: [TrailSegment] = []
        for i in 0..<(located.count - 1) {
            let current = located[i]
            let next = located[i + 1]

            // Skip large time gaps (different trips)
            let gap = next.timestamp.timeIntervalSince(current.timestamp)
            guard gap < maxGapSeconds else { continue }

            segments.append(TrailSegment(
                start: CLLocationCoordinate2D(latitude: current.latitude, longitude: current.longitude),
                end: CLLocationCoordinate2D(latitude: next.latitude, longitude: next.longitude),
                quality: current.qualityLevel,
                locationSource: LocationSource(rawValue: current.locationSource) ?? .coreLocation
            ))
        }
        return segments
    }
}

// MARK: - Quality Polyline

/// Custom MKPolyline subclass that carries quality and source metadata.
/// Used by the map delegate to color each segment appropriately.
final class QualityPolyline: MKPolyline {
    var quality: LatencyQuality = .unknown
    var locationSource: LocationSource = .coreLocation
}

// MARK: - Trail Map View (NSViewRepresentable)

/// An MKMapView wrapper that renders quality trail polylines and annotations.
/// Replaces the SwiftUI Map for proper polyline + annotation rendering.
struct TrailMapView: NSViewRepresentable {
    let records: [QualityRecord]
    let segments: [TrailSegment]
    let currentLatitude: Double?
    let currentLongitude: Double?
    let currentBearing: Double
    @Binding var region: MKCoordinateRegion
    @Binding var selectedRecord: QualityRecord?

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
        context.coordinator.parent = self

        // Update region
        mapView.setRegion(region, animated: true)

        // Remove old overlays and annotations
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)

        // Add trail polylines
        for segment in segments {
            var coords = [segment.start, segment.end]
            let polyline = QualityPolyline(coordinates: &coords, count: 2)
            polyline.quality = segment.quality
            polyline.locationSource = segment.locationSource
            mapView.addOverlay(polyline)
        }

        // Add record annotations (filtered — skip None and Interpolated)
        let visibleRecords = records.filter { record in
            let source = LocationSource(rawValue: record.locationSource) ?? .coreLocation
            return source != .none && source != .interpolated &&
                   (record.latitude != 0 && record.longitude != 0)
        }

        for record in visibleRecords {
            let annotation = QualityAnnotation(record: record)
            annotation.coordinate = CLLocationCoordinate2D(
                latitude: record.latitude,
                longitude: record.longitude
            )
            mapView.addAnnotation(annotation)
        }

        // Add live position marker
        if let lat = currentLatitude, let lon = currentLongitude {
            let liveAnnotation = LivePositionAnnotation()
            liveAnnotation.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            liveAnnotation.bearing = currentBearing
            mapView.addAnnotation(liveAnnotation)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: TrailMapView

        init(parent: TrailMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? QualityPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = nsColor(for: polyline.quality, source: polyline.locationSource)
                renderer.lineWidth = polyline.locationSource == .interpolated ? 2 : 4
                if polyline.locationSource == .interpolated || polyline.locationSource == .ipGeolocation {
                    renderer.lineDashPattern = [6, 4]
                }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let liveAnnotation = annotation as? LivePositionAnnotation {
                return livePositionView(for: liveAnnotation, in: mapView)
            }

            if let qualityAnnotation = annotation as? QualityAnnotation {
                return qualityDotView(for: qualityAnnotation, in: mapView)
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let qualityAnnotation = view.annotation as? QualityAnnotation {
                DispatchQueue.main.async {
                    self.parent.selectedRecord = qualityAnnotation.record
                }
            }
            if let annotation = view.annotation {
                mapView.deselectAnnotation(annotation, animated: false)
            }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            DispatchQueue.main.async {
                self.parent.region = mapView.region
            }
        }

        // MARK: - View Builders

        private func qualityDotView(
            for annotation: QualityAnnotation,
            in mapView: MKMapView
        ) -> MKAnnotationView {
            let id = "QualityDot"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation

            let record = annotation.record
            let source = LocationSource(rawValue: record.locationSource) ?? .coreLocation
            let quality = record.qualityLevel

            let size: CGFloat
            let opacity: Double
            switch source {
            case .coreLocation:
                size = record.wasSuccessful ? 10 : 7
                opacity = 0.8
            case .lowAccuracy:
                size = 8
                opacity = 0.5
            case .ipGeolocation:
                size = 20
                opacity = 0.3
            default:
                size = 8
                opacity = 0.6
            }

            let color = quality.swiftUIColor.opacity(opacity)
            let hostingView = NSHostingView(rootView:
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle().stroke(quality.swiftUIColor.opacity(opacity + 0.2), lineWidth: 1)
                    )
            )
            hostingView.frame = CGRect(x: 0, y: 0, width: size + 4, height: size + 4)

            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(hostingView)
            view.frame = hostingView.frame
            view.centerOffset = CGPoint(x: 0, y: 0)

            return view
        }

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

        private func nsColor(for quality: LatencyQuality, source: LocationSource) -> NSColor {
            let opacity: CGFloat = (source == .interpolated || source == .ipGeolocation) ? 0.4 : 0.7
            switch quality {
            case .excellent, .good: return NSColor.systemGreen.withAlphaComponent(opacity)
            case .fair:             return NSColor.systemYellow.withAlphaComponent(opacity)
            case .poor:             return NSColor.systemOrange.withAlphaComponent(opacity)
            case .bad:              return NSColor.systemRed.withAlphaComponent(opacity)
            case .unknown:          return NSColor.systemGray.withAlphaComponent(opacity)
            }
        }
    }
}

// MARK: - Annotation Types

/// Annotation for a quality measurement dot on the map.
final class QualityAnnotation: NSObject, MKAnnotation {
    let record: QualityRecord
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(record: QualityRecord) {
        self.record = record
        self.coordinate = CLLocationCoordinate2D(
            latitude: record.latitude,
            longitude: record.longitude
        )
    }
}

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
            // Outer pulse ring
            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: isPulsing ? 40 : 24, height: isPulsing ? 40 : 24)
                .animation(
                    .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            // Inner solid dot
            Circle()
                .fill(Color.blue)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))

            // Bearing arrow (direction of travel)
            Image(systemName: "location.north.fill")
                .font(.system(size: 10))
                .foregroundColor(.blue)
                .rotationEffect(.degrees(bearing))
                .offset(y: -18)
        }
        .onAppear { isPulsing = true }
    }
}
