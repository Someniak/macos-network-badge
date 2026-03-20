// ---------------------------------------------------------
// GPS2IPSource.swift — TCP client for GPS2IP iPhone GPS streaming
//
// Connects to the GPS2IP iOS app (capsicumdreams.com/gps2ip) which
// streams NMEA sentences over a TCP socket (default port 11123).
// Parses GPRMC/GNRMC for position/speed/bearing and GPGGA/GNGGA
// for HDOP/altitude, then calls onLocation with a CLLocation.
//
// Supports multiple endpoints (e.g. hotspot IP + USB tethering IP).
// Tries all endpoints simultaneously; uses whichever connects first.
// ---------------------------------------------------------

import CoreLocation
import Foundation
import Network

// MARK: - Endpoint

/// A single GPS2IP endpoint (host + port).
struct GPS2IPEndpoint: Identifiable, Equatable, Codable {
    var id = UUID()
    var host: String
    var port: Int

    var displayLabel: String {
        "\(host):\(port)"
    }
}

// MARK: - GPS2IPSource

final class GPS2IPSource: ObservableObject, @unchecked Sendable {

    // MARK: - Persisted Settings

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "gps2ipEnabled") }
    }

    @Published var endpoints: [GPS2IPEndpoint] {
        didSet { saveEndpoints() }
    }

    // MARK: - Status (read-only from outside)

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var errorMessage: String? = nil
    @Published private(set) var lastFixAt: Date? = nil

    /// Which endpoint is currently providing fixes (nil if none)
    @Published private(set) var activeEndpoint: GPS2IPEndpoint? = nil

    /// Whether GPS2IP is connected AND actively providing fixes (not stale).
    /// Returns false if the last fix is older than 15 seconds, even if the
    /// TCP connection is still open (e.g. app backgrounded on iPhone).
    var isActivelyFixing: Bool {
        guard isConnected, let last = lastFixAt else { return false }
        return -last.timeIntervalSinceNow < 15
    }

    // MARK: - Callback

    /// Called on the main thread whenever a valid NMEA fix is parsed.
    var onLocation: ((CLLocation) -> Void)?

    // MARK: - Internals

    /// One live TCP connection per endpoint
    private var connections: [UUID: NWConnection] = [:]
    private var receiveBuffers: [UUID: Data] = [:]
    private let queue = DispatchQueue(label: "GPS2IPSource")

    /// Latest HDOP value from GGA sentences (used for next RMC fix)
    private var latestHDOP: Double = 2.0
    /// Latest altitude from GGA sentences
    private var latestAltitude: Double = 0.0

    // MARK: - Legacy Migration

    /// Migrates old single-host/port settings to the new endpoints array.
    private static func migrateLegacySettings() -> [GPS2IPEndpoint]? {
        let defaults = UserDefaults.standard
        guard let host = defaults.string(forKey: "gps2ipHost"), !host.isEmpty else { return nil }
        let port = defaults.integer(forKey: "gps2ipPort")
        let endpoint = GPS2IPEndpoint(host: host, port: port > 0 ? port : 11123)
        // Clean up legacy keys
        defaults.removeObject(forKey: "gps2ipHost")
        defaults.removeObject(forKey: "gps2ipPort")
        return [endpoint]
    }

    // MARK: - Init

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: "gps2ipEnabled")

        if let data = UserDefaults.standard.data(forKey: "gps2ipEndpoints"),
           let decoded = try? JSONDecoder().decode([GPS2IPEndpoint].self, from: data),
           !decoded.isEmpty {
            endpoints = decoded
        } else if let migrated = GPS2IPSource.migrateLegacySettings() {
            endpoints = migrated
        } else {
            endpoints = []
        }
    }

    private func saveEndpoints() {
        if let data = try? JSONEncoder().encode(endpoints) {
            UserDefaults.standard.set(data, forKey: "gps2ipEndpoints")
        }
    }

    // MARK: - Public API

    func start() {
        guard isEnabled, !endpoints.isEmpty else { return }
        stopAll()

        for endpoint in endpoints {
            startConnection(for: endpoint)
        }
    }

    func stop() {
        stopAll()
    }

    private func stopAll() {
        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        receiveBuffers.removeAll()
        DispatchQueue.main.async {
            self.isConnected = false
            self.errorMessage = nil
            self.activeEndpoint = nil
        }
    }

    // MARK: - Per-Endpoint Connection

    private func startConnection(for endpoint: GPS2IPEndpoint) {
        guard let portValue = NWEndpoint.Port(rawValue: UInt16(endpoint.port)) else { return }

        let conn = NWConnection(
            host: NWEndpoint.Host(endpoint.host),
            port: portValue,
            using: .tcp
        )

        let endpointID = endpoint.id

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    // First connection to become ready wins
                    if !self.isConnected {
                        self.isConnected = true
                        self.activeEndpoint = endpoint
                        self.errorMessage = nil
                    }
                }
            case .failed(let err):
                DispatchQueue.main.async {
                    self.connections.removeValue(forKey: endpointID)
                    self.receiveBuffers.removeValue(forKey: endpointID)
                    // Only show error if no other connection is active
                    if self.activeEndpoint?.id == endpointID {
                        self.isConnected = false
                        self.activeEndpoint = nil
                        self.errorMessage = err.localizedDescription
                    }
                    if self.connections.isEmpty {
                        self.isConnected = false
                        self.errorMessage = err.localizedDescription
                    }
                }
                self.scheduleReconnect(endpoint: endpoint)
            case .cancelled:
                DispatchQueue.main.async {
                    self.connections.removeValue(forKey: endpointID)
                    self.receiveBuffers.removeValue(forKey: endpointID)
                    if self.activeEndpoint?.id == endpointID {
                        self.isConnected = self.connections.values.contains { $0.state == .ready }
                        self.activeEndpoint = nil
                    }
                }
            default:
                break
            }
        }

        connections[endpointID] = conn
        receiveBuffers[endpointID] = Data()
        conn.start(queue: queue)
        receiveNext(conn, endpointID: endpointID)
    }

    // MARK: - TCP Receive Loop

    private func receiveNext(_ conn: NWConnection, endpointID: UUID) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                if self.receiveBuffers[endpointID] != nil {
                    self.receiveBuffers[endpointID]!.append(data)
                } else {
                    self.receiveBuffers[endpointID] = data
                }
            }
            self.drainBuffer(endpointID: endpointID)
            if !isComplete && error == nil { self.receiveNext(conn, endpointID: endpointID) }
        }
    }

    private func drainBuffer(endpointID: UUID) {
        guard let buffer = receiveBuffers[endpointID],
              let string = String(data: buffer, encoding: .ascii) else { return }
        var lines = string.components(separatedBy: "\n")
        let incomplete = lines.removeLast()
        receiveBuffers[endpointID] = incomplete.data(using: .ascii) ?? Data()
        let endpoint = endpoints.first { $0.id == endpointID }
        for line in lines {
            parseNMEA(line.trimmingCharacters(in: .whitespacesAndNewlines), fromEndpoint: endpoint)
        }
    }

    // MARK: - Reconnect

    private func scheduleReconnect(endpoint: GPS2IPEndpoint) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.isEnabled else { return }
            // Only reconnect if this endpoint is still in the list
            guard self.endpoints.contains(where: { $0.id == endpoint.id }) else { return }
            self.startConnection(for: endpoint)
        }
    }

    // MARK: - NMEA Parsing

    private func parseNMEA(_ sentence: String, fromEndpoint endpoint: GPS2IPEndpoint?) {
        guard sentence.hasPrefix("$") else { return }
        guard validateChecksum(sentence) else { return }

        let body: String
        if let star = sentence.firstIndex(of: "*") {
            body = String(sentence[sentence.index(after: sentence.startIndex)..<star])
        } else {
            body = String(sentence.dropFirst())
        }

        let fields = body.components(separatedBy: ",")
        guard !fields.isEmpty else { return }

        switch fields[0] {
        case "GPRMC", "GNRMC":
            parseRMC(fields, fromEndpoint: endpoint)
        case "GPGGA", "GNGGA":
            parseGGA(fields)
        default:
            break
        }
    }

    private func validateChecksum(_ sentence: String) -> Bool {
        guard let star = sentence.lastIndex(of: "*") else { return true }
        let checksumStr = String(sentence[sentence.index(after: star)...])
        guard let expected = UInt8(checksumStr, radix: 16) else { return false }

        var xor: UInt8 = 0
        for char in sentence.unicodeScalars.dropFirst() {
            if char == "*" { break }
            xor ^= UInt8(char.value & 0xFF)
        }
        return xor == expected
    }

    private func parseRMC(_ fields: [String], fromEndpoint endpoint: GPS2IPEndpoint?) {
        guard fields.count >= 9 else { return }
        guard fields[2] == "A" else { return }

        guard let lat = parseDMM(fields[3], direction: fields[4]),
              let lon = parseDMM(fields[5], direction: fields[6]) else { return }

        let speedMs = Double(fields[7]).map { $0 * 0.51444 } ?? 0.0
        let bearing = Double(fields[8]) ?? 0.0

        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: latestAltitude,
            horizontalAccuracy: latestHDOP * 5.0,
            verticalAccuracy: -1,
            course: bearing,
            speed: speedMs,
            timestamp: Date()
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastFixAt = Date()
            self.isConnected = true
            self.activeEndpoint = endpoint
            self.onLocation?(location)
        }
    }

    private func parseGGA(_ fields: [String]) {
        guard fields.count >= 10 else { return }
        guard fields[6] != "0" else { return }

        if let hdop = Double(fields[8]), hdop > 0 {
            latestHDOP = hdop
        }
        if let alt = Double(fields[9]) {
            latestAltitude = alt
        }
    }

    private func parseDMM(_ value: String, direction: String) -> Double? {
        guard !value.isEmpty, let raw = Double(value) else { return nil }
        let degrees = (raw / 100).rounded(.towardZero)
        let minutes = raw.truncatingRemainder(dividingBy: 100)
        var decimal = degrees + minutes / 60.0
        if direction == "S" || direction == "W" { decimal = -decimal }
        return decimal
    }
}
