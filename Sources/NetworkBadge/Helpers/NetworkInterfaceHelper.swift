// ---------------------------------------------------------
// NetworkInterfaceHelper.swift — Detect network interface details
//
// This helper figures out WHAT kind of network you're on
// beyond just "WiFi" or "Ethernet". For example, when you
// connect your iPhone via USB cable, macOS creates a bridge
// interface — this helper detects that as "USB Tethering".
//
// All functions here are pure/static for easy testing.
// ---------------------------------------------------------

import Foundation

/// Helper to identify network interface types from their system names.
/// macOS names interfaces like "en0" (WiFi), "en6" (USB Ethernet),
/// "bridge100" (iPhone USB tethering), etc.
enum NetworkInterfaceHelper {

    // MARK: - Interface Type Detection

    /// Determines the connection type from a macOS network interface name.
    ///
    /// How macOS names interfaces:
    ///   - "en0"       → usually the built-in WiFi adapter
    ///   - "en1"-"en9" → additional network adapters (USB Ethernet, Thunderbolt, etc.)
    ///   - "bridge100" → iPhone USB tethering (macOS bridges the connection)
    ///   - "lo0"       → loopback (localhost)
    ///   - "utun*"     → VPN tunnels
    ///   - "awdl0"     → Apple Wireless Direct Link (AirDrop)
    ///   - "llw0"      → Low Latency WLAN (used by AirDrop/AirPlay)
    ///
    /// - Parameter interfaceName: The system interface name (e.g. "en0", "bridge100")
    /// - Returns: A `ConnectionType` describing what kind of connection this is
    static func connectionType(fromInterfaceName interfaceName: String) -> ConnectionType {
        let name = interfaceName.lowercased()

        // iPhone USB tethering creates a "bridge" interface
        if name.hasPrefix("bridge") {
            return .usbTethering
        }

        // VPN tunnel interfaces
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") {
            return .unknown  // VPN — the underlying type varies
        }

        // Loopback (localhost — not a real network)
        if name == "lo0" {
            return .loopback
        }

        // AirDrop/AirPlay interfaces — not internet connections
        if name.hasPrefix("awdl") || name.hasPrefix("llw") {
            return .unknown
        }

        // "en*" interfaces could be WiFi, Ethernet, or USB adapters
        // We can't tell from the name alone — the caller should use
        // NWPathMonitor's interface type for the final decision
        if name.hasPrefix("en") {
            return .unknown  // needs NWPathMonitor to distinguish WiFi vs Ethernet
        }

        return .unknown
    }

    /// Checks if an interface name looks like iPhone USB tethering.
    ///
    /// When you plug your iPhone in and enable "Personal Hotspot" via USB,
    /// macOS creates a bridge interface (usually "bridge100").
    ///
    /// - Parameter interfaceName: The system interface name
    /// - Returns: true if this looks like a tethering bridge
    static func isUSBTethering(interfaceName: String) -> Bool {
        return interfaceName.lowercased().hasPrefix("bridge")
    }

    /// Checks if an interface name is a VPN tunnel.
    ///
    /// - Parameter interfaceName: The system interface name
    /// - Returns: true if this is a VPN tunnel interface
    static func isVPN(interfaceName: String) -> Bool {
        let name = interfaceName.lowercased()
        return name.hasPrefix("utun") || name.hasPrefix("ipsec")
    }

    // MARK: - Human-Readable Names

    /// Returns a friendly description for a network interface name.
    ///
    /// Examples:
    ///   - "en0" → "en0 (WiFi / Ethernet)"
    ///   - "bridge100" → "bridge100 (USB Tethering)"
    ///   - "lo0" → "lo0 (Loopback)"
    ///
    /// - Parameter interfaceName: The system interface name
    /// - Returns: A human-readable description
    static func displayName(forInterface interfaceName: String) -> String {
        let name = interfaceName.lowercased()

        if name.hasPrefix("bridge") {
            return "\(interfaceName) (USB Tethering)"
        }
        if name == "lo0" {
            return "\(interfaceName) (Loopback)"
        }
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") {
            return "\(interfaceName) (VPN)"
        }
        if name.hasPrefix("en") {
            return "\(interfaceName) (WiFi / Ethernet)"
        }
        if name.hasPrefix("awdl") {
            return "\(interfaceName) (AirDrop)"
        }

        return interfaceName
    }
}
