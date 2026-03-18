// ---------------------------------------------------------
// NetworkInterfaceHelperTests.swift — Tests for interface detection
//
// These tests verify that we correctly identify different
// network interface types from their macOS system names.
// ---------------------------------------------------------

import XCTest
@testable import NetworkBadge

final class NetworkInterfaceHelperTests: XCTestCase {

    // MARK: - USB Tethering Detection

    /// iPhone USB tethering creates "bridge" interfaces
    func testBridgeInterfaceIsUSBTethering() {
        XCTAssertTrue(NetworkInterfaceHelper.isUSBTethering(interfaceName: "bridge100"))
        XCTAssertTrue(NetworkInterfaceHelper.isUSBTethering(interfaceName: "bridge0"))
        XCTAssertTrue(NetworkInterfaceHelper.isUSBTethering(interfaceName: "bridge200"))
    }

    /// Regular interfaces should NOT be detected as USB tethering
    func testNonBridgeIsNotUSBTethering() {
        XCTAssertFalse(NetworkInterfaceHelper.isUSBTethering(interfaceName: "en0"))
        XCTAssertFalse(NetworkInterfaceHelper.isUSBTethering(interfaceName: "en1"))
        XCTAssertFalse(NetworkInterfaceHelper.isUSBTethering(interfaceName: "lo0"))
        XCTAssertFalse(NetworkInterfaceHelper.isUSBTethering(interfaceName: "utun0"))
    }

    // MARK: - VPN Detection

    /// VPN tunnel interfaces start with "utun" or "ipsec"
    func testVPNDetection() {
        XCTAssertTrue(NetworkInterfaceHelper.isVPN(interfaceName: "utun0"))
        XCTAssertTrue(NetworkInterfaceHelper.isVPN(interfaceName: "utun1"))
        XCTAssertTrue(NetworkInterfaceHelper.isVPN(interfaceName: "ipsec0"))
    }

    /// Regular interfaces should NOT be detected as VPN
    func testNonVPNInterfaces() {
        XCTAssertFalse(NetworkInterfaceHelper.isVPN(interfaceName: "en0"))
        XCTAssertFalse(NetworkInterfaceHelper.isVPN(interfaceName: "bridge100"))
        XCTAssertFalse(NetworkInterfaceHelper.isVPN(interfaceName: "lo0"))
    }

    // MARK: - Connection Type from Interface Name

    /// Bridge interfaces should map to USB tethering
    func testConnectionTypeForBridge() {
        let type = NetworkInterfaceHelper.connectionType(fromInterfaceName: "bridge100")
        XCTAssertEqual(type, .usbTethering)
    }

    /// Loopback should map to .loopback
    func testConnectionTypeForLoopback() {
        let type = NetworkInterfaceHelper.connectionType(fromInterfaceName: "lo0")
        XCTAssertEqual(type, .loopback)
    }

    /// "en*" interfaces return .unknown because they need NWPathMonitor
    /// to distinguish between WiFi and Ethernet
    func testConnectionTypeForEnInterfaces() {
        XCTAssertEqual(
            NetworkInterfaceHelper.connectionType(fromInterfaceName: "en0"),
            .unknown
        )
        XCTAssertEqual(
            NetworkInterfaceHelper.connectionType(fromInterfaceName: "en1"),
            .unknown
        )
    }

    /// VPN tunnel interfaces return .unknown
    func testConnectionTypeForVPN() {
        XCTAssertEqual(
            NetworkInterfaceHelper.connectionType(fromInterfaceName: "utun0"),
            .unknown
        )
    }

    /// AirDrop interfaces return .unknown
    func testConnectionTypeForAirDrop() {
        XCTAssertEqual(
            NetworkInterfaceHelper.connectionType(fromInterfaceName: "awdl0"),
            .unknown
        )
    }

    // MARK: - Display Names

    /// Verify human-readable names include helpful descriptions
    func testDisplayNames() {
        let bridgeName = NetworkInterfaceHelper.displayName(forInterface: "bridge100")
        XCTAssertTrue(bridgeName.contains("USB Tethering"))

        let loopbackName = NetworkInterfaceHelper.displayName(forInterface: "lo0")
        XCTAssertTrue(loopbackName.contains("Loopback"))

        let vpnName = NetworkInterfaceHelper.displayName(forInterface: "utun0")
        XCTAssertTrue(vpnName.contains("VPN"))

        let enName = NetworkInterfaceHelper.displayName(forInterface: "en0")
        XCTAssertTrue(enName.contains("WiFi") || enName.contains("Ethernet"))

        let airdropName = NetworkInterfaceHelper.displayName(forInterface: "awdl0")
        XCTAssertTrue(airdropName.contains("AirDrop"))
    }

    /// Unknown interfaces should just return the raw name
    func testDisplayNameUnknown() {
        let name = NetworkInterfaceHelper.displayName(forInterface: "xyz99")
        XCTAssertEqual(name, "xyz99")
    }

    // MARK: - Case Sensitivity

    /// Interface name detection should be case-insensitive
    func testCaseInsensitive() {
        XCTAssertTrue(NetworkInterfaceHelper.isUSBTethering(interfaceName: "Bridge100"))
        XCTAssertTrue(NetworkInterfaceHelper.isUSBTethering(interfaceName: "BRIDGE100"))
        XCTAssertTrue(NetworkInterfaceHelper.isVPN(interfaceName: "UTUN0"))
    }
}
