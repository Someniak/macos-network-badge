// swift-tools-version: 5.9
// ---------------------------------------------------------
// Package.swift — Swift Package Manager manifest
//
// This defines the app as an executable Swift package for both
// macOS (menu bar app) and iOS (tab-based GPS tracking app).
//
// Both platforms share the same source directory and use
// #if os(macOS) / #if os(iOS) for platform-specific code.
//
// Usage:
//   macOS: swift build / swift run NetworkBadge
//   iOS:   Open in Xcode, select iOS simulator/device target
// ---------------------------------------------------------

import PackageDescription

let package = Package(
    name: "NetworkBadge",

    // Requires macOS 13+ for MenuBarExtra, iOS 16+ for NavigationStack
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],

    targets: [
        // ── Main App ──────────────────────────────────────
        .executableTarget(
            name: "NetworkBadge",
            path: "Sources/NetworkBadge",
            linkerSettings: [
                // CoreWLAN: needed to read WiFi SSID and signal strength (macOS only)
                .linkedFramework("CoreWLAN", .when(platforms: [.macOS])),
                // CoreLocation: needed for GPS tracking of network quality
                .linkedFramework("CoreLocation"),
                // MapKit: needed for the quality map view
                .linkedFramework("MapKit"),
                // SQLite3: needed for persistent quality record storage
                .linkedLibrary("sqlite3"),
            ]
        ),

        // ── Unit Tests ───────────────────────────────────
        .testTarget(
            name: "NetworkBadgeTests",
            dependencies: ["NetworkBadge"],
            path: "Tests/NetworkBadgeTests"
        ),
    ]
)
