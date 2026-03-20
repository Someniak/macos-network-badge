// ---------------------------------------------------------
// CoordinateUtils.swift — Shared coordinate math
//
// Haversine forward projection used by dead reckoning and
// spatial lookahead prediction. Extracted from LocationMonitor
// so multiple modules can share it.
// ---------------------------------------------------------

import CoreLocation

enum CoordinateUtils {

    /// Haversine forward projection: move `distance` metres from `coord` along `bearing` degrees.
    static func projectCoordinate(
        from coord: CLLocationCoordinate2D,
        distance: Double,
        bearing: Double
    ) -> CLLocationCoordinate2D {
        let R = 6_371_000.0
        let d = distance / R
        let bearingRad = bearing * .pi / 180
        let lat1 = coord.latitude * .pi / 180
        let lon1 = coord.longitude * .pi / 180

        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(bearingRad))
        let lon2 = lon1 + atan2(
            sin(bearingRad) * sin(d) * cos(lat1),
            cos(d) - sin(lat1) * sin(lat2)
        )
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}
