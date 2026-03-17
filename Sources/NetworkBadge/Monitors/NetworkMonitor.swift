// ---------------------------------------------------------
// NetworkMonitor.swift — Detects your network connection type
//
// This monitor watches for network changes using Apple's
// NWPathMonitor. When you switch from WiFi to Ethernet, or
// plug in your iPhone for USB tethering, this class detects
// it and updates the published properties.
//
// It also reads the WiFi network name (SSID) when on WiFi,
// so you can see "NMBS-WiFi" or "Starbucks" in the UI.
// ---------------------------------------------------------

import Foundation
import Network        // Apple's Network framework — provides NWPathMonitor
import Combine

#if canImport(CoreWLAN)
import CoreWLAN       // macOS framework to read WiFi details (SSID, signal)
#endif

/// Monitors the current network connection and publishes changes.
///
/// Usage:
///   let monitor = NetworkMonitor()
///   monitor.start()   // begins watching
///   // read monitor.connectionType, monitor.wifiSSID, etc.
///   monitor.stop()    // stop watching (e.g. when app quits)
///
final class NetworkMonitor: ObservableObject {

    // MARK: - Published Properties (the UI reads these)

    /// What kind of connection: WiFi, Ethernet, USB Tethering, etc.
    @Published var connectionType: ConnectionType = .unknown

    /// The system name of the active interface (e.g. "en0", "bridge100")
    @Published var interfaceName: String = ""

    /// The WiFi network name, if on WiFi (e.g. "NMBS-WiFi")
    /// Will be nil when not on WiFi.
    @Published var wifiSSID: String? = nil

    /// WiFi signal strength in dBm (nil when not on WiFi)
    /// Typical values: -30 (strong) to -90 (very weak)
    @Published var wifiRSSI: Int? = nil

    /// Whether we have any network connection at all
    @Published var isConnected: Bool = false

    // MARK: - Private Properties

    /// Apple's built-in network path monitor — fires whenever
    /// the network situation changes (WiFi drops, cable plugged in, etc.)
    private let pathMonitor = NWPathMonitor()

    /// Dedicated background queue for network monitoring
    /// (we don't want to block the main thread)
    private let monitorQueue = DispatchQueue(
        label: "com.networkbadge.network-monitor",
        qos: .utility
    )

    // MARK: - Start / Stop

    /// Begin monitoring network changes.
    /// Call this when the app launches.
    func start() {
        // This closure fires every time the network situation changes
        pathMonitor.pathUpdateHandler = { [weak self] path in
            // Switch to main thread because we're updating @Published properties
            // (SwiftUI requires UI updates on the main thread)
            DispatchQueue.main.async {
                self?.handlePathUpdate(path)
            }
        }

        // Start monitoring on our background queue
        pathMonitor.start(queue: monitorQueue)
    }

    /// Stop monitoring. Call this when the app quits.
    func stop() {
        pathMonitor.cancel()
    }

    // MARK: - Path Update Handling

    /// Called whenever the network changes. Determines what type of
    /// connection we're on and updates all published properties.
    private func handlePathUpdate(_ path: NWPath) {
        // Are we connected at all?
        isConnected = (path.status == .satisfied)

        guard isConnected else {
            // No connection — clear everything
            connectionType = .disconnected
            interfaceName = ""
            wifiSSID = nil
            wifiRSSI = nil
            return
        }

        // Get the first available interface (the one actively carrying traffic)
        if let activeInterface = path.availableInterfaces.first {
            interfaceName = activeInterface.name

            // First, check if this is USB tethering (bridge interface)
            if NetworkInterfaceHelper.isUSBTethering(interfaceName: activeInterface.name) {
                connectionType = .usbTethering
                wifiSSID = nil
                wifiRSSI = nil
                return
            }

            // Use NWPathMonitor's interface type detection
            switch activeInterface.type {
            case .wifi:
                connectionType = .wifi
                wifiSSID = readCurrentWiFiSSID()
                wifiRSSI = readCurrentWiFiRSSI()

            case .wiredEthernet:
                connectionType = .ethernet
                wifiSSID = nil
                wifiRSSI = nil

            case .cellular:
                connectionType = .cellular
                wifiSSID = nil
                wifiRSSI = nil

            case .loopback:
                connectionType = .loopback
                wifiSSID = nil
                wifiRSSI = nil

            default:
                connectionType = .unknown
                wifiSSID = nil
                wifiRSSI = nil
            }
        } else {
            // Connected but no interface info available
            connectionType = .unknown
            interfaceName = ""
            wifiSSID = nil
            wifiRSSI = nil
        }
    }

    // MARK: - WiFi SSID Reading

    /// Reads the current WiFi network name (SSID) using CoreWLAN.
    ///
    /// CoreWLAN is a macOS-only framework that talks to the WiFi hardware.
    /// Returns nil if not on WiFi or if the SSID can't be read.
    ///
    /// Note: On macOS 14+, this may require location permissions or
    /// the "com.apple.developer.networking.wifi-info" entitlement
    /// for App Store builds. For local development it works fine.
    private func readCurrentWiFiSSID() -> String? {
        #if canImport(CoreWLAN)
        // CWWiFiClient is the main entry point for CoreWLAN
        let wifiClient = CWWiFiClient.shared()

        // .interface() returns the default WiFi interface (usually en0)
        guard let wifiInterface = wifiClient.interface() else {
            return nil
        }

        // .ssid() returns the name of the connected WiFi network
        return wifiInterface.ssid()
        #else
        return nil
        #endif
    }

    // MARK: - WiFi RSSI Reading

    /// Reads the current WiFi signal strength (RSSI) in dBm using CoreWLAN.
    ///
    /// Typical values:
    ///   - -30 to -50 dBm: Excellent signal
    ///   - -50 to -60 dBm: Good signal
    ///   - -60 to -70 dBm: Fair signal
    ///   - Below -70 dBm: Weak signal
    private func readCurrentWiFiRSSI() -> Int? {
        #if canImport(CoreWLAN)
        let wifiClient = CWWiFiClient.shared()
        guard let wifiInterface = wifiClient.interface() else {
            return nil
        }
        // rssiValue() returns the current signal strength in dBm
        let rssi = wifiInterface.rssiValue()
        // rssiValue() returns 0 if not associated with a network
        return rssi == 0 ? nil : rssi
        #else
        return nil
        #endif
    }
}
