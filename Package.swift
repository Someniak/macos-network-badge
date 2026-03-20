// swift-tools-version: 5.9
// ---------------------------------------------------------
// Package.swift — Swift Package Manager manifest
//
// This defines our macOS app as an executable Swift package.
// Open this file in Xcode to build and run the app, or use
// `swift build` from the command line.
// ---------------------------------------------------------

import PackageDescription

let package = Package(
    name: "NetworkBadge",

    // Requires macOS 13+ for SwiftUI's MenuBarExtra
    platforms: [
        .macOS(.v13)
    ],

    targets: [
        // ── Main App ──────────────────────────────────────
        .executableTarget(
            name: "NetworkBadge",
            path: "Sources/NetworkBadge",
            linkerSettings: [
                // CoreWLAN: needed to read WiFi SSID and signal strength
                .linkedFramework("CoreWLAN"),
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
