// ---------------------------------------------------------
// IOSSettingsView.swift — iOS settings
//
// Form-based settings adapted for iOS. No "Launch at Login"
// (iOS handles that). No GPS2IP (iOS has native GPS).
// Focused on GPS tracking settings, notifications, and
// polling configuration.
// ---------------------------------------------------------

#if os(iOS)
import SwiftUI

struct IOSSettingsView: View {

    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject var locationMonitor: LocationMonitor
    @ObservedObject var latencyMonitor: LatencyMonitor
    @ObservedObject var updateChecker: UpdateChecker

    /// Preset poll targets
    private let presetTargets: [(label: String, url: String)] = [
        ("Apple (captive.apple.com)", "http://captive.apple.com/hotspot-detect.html"),
        ("Cloudflare (cp.cloudflare.com)", "http://cp.cloudflare.com/generate_204"),
    ]

    private var isCustomTarget: Bool {
        !presetTargets.contains { $0.url == latencyMonitor.targetURL.absoluteString }
    }

    @State private var customTargetText: String = ""
    @State private var showCustomField: Bool = false
    @State private var repairResult: String?

    var body: some View {
        NavigationStack {
            Form {
                notificationsSection
                pollingSection
                gpsTrackingSection
                aboutSection
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Enable Notifications", isOn: $notificationManager.notificationsEnabled)
            if notificationManager.notificationsEnabled {
                Toggle("Latency degradation", isOn: $notificationManager.latencyAlertsEnabled)
                Toggle("Connection lost", isOn: $notificationManager.disconnectionAlertsEnabled)
                Toggle("Rough connection ahead", isOn: $notificationManager.predictionAlertsEnabled)
                if notificationManager.predictionAlertsEnabled && !locationMonitor.isTrackingEnabled {
                    Text("Requires GPS tracking to be enabled.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    // MARK: - Polling

    private var pollingSection: some View {
        Section("Polling") {
            Stepper("Interval: \(Int(latencyMonitor.measurementInterval)) s",
                    value: $latencyMonitor.measurementInterval,
                    in: 1...60, step: 1)

            Picker("Target", selection: Binding(
                get: {
                    isCustomTarget ? "custom" : latencyMonitor.targetURL.absoluteString
                },
                set: { selected in
                    if selected == "custom" {
                        customTargetText = latencyMonitor.targetURL.absoluteString
                        showCustomField = true
                    } else if let url = URL(string: selected) {
                        latencyMonitor.targetURL = url
                        showCustomField = false
                    }
                }
            )) {
                ForEach(presetTargets, id: \.url) { preset in
                    Text(preset.label).tag(preset.url)
                }
                Text("Custom…").tag("custom")
            }

            if showCustomField || isCustomTarget {
                TextField("URL", text: $customTargetText)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .onAppear {
                        if isCustomTarget {
                            customTargetText = latencyMonitor.targetURL.absoluteString
                            showCustomField = true
                        }
                    }
                    .onSubmit {
                        if let url = URL(string: customTargetText), !customTargetText.isEmpty {
                            latencyMonitor.targetURL = url
                        }
                    }
                Text("Use a plain HTTP URL that returns 2xx with no redirects.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - GPS Tracking

    private var gpsTrackingSection: some View {
        Section("GPS Tracking") {
            Toggle("Enable GPS Tracking", isOn: $locationMonitor.isTrackingEnabled)
            Text("Record your location alongside network measurements to build a quality map of your route.")
                .font(.caption)
                .foregroundColor(.secondary)

            if locationMonitor.isTrackingEnabled {
                Stepper("Record every \(Int(locationMonitor.minimumDistance)) m",
                        value: $locationMonitor.minimumDistance,
                        in: 5...500, step: 5)
                Text("Minimum distance before recording a new point.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Stepper("Min interval: \(Int(locationMonitor.minimumInterval)) s",
                        value: $locationMonitor.minimumInterval,
                        in: 1...120, step: 1)
                Text("Minimum seconds between recordings.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Stepper(
                    "Stationary slowdown: \(String(format: "%.1f", locationMonitor.stationaryMultiplier))×",
                    value: $locationMonitor.stationaryMultiplier,
                    in: 1.5...4.0,
                    step: 0.5
                )
                Text("Polling slows by this factor when stationary to save battery.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Location Intelligence
                Section("Location Intelligence") {
                    Stepper("Accuracy threshold: \(Int(locationMonitor.intelligence.accuracyThreshold)) m",
                            value: $locationMonitor.intelligence.accuracyThreshold,
                            in: 200...5000, step: 200)
                    Text("Readings less accurate than this are discarded.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("IP geolocation fallback",
                           isOn: $locationMonitor.intelligence.ipGeolocationEnabled)
                    Text("Estimate location from IP when GPS is unavailable.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Stepper("Fill gaps up to: \(Int(locationMonitor.intelligence.maxInterpolationGap / 60)) min",
                            value: $locationMonitor.intelligence.maxInterpolationGap,
                            in: 60...600, step: 60)

                    Button("Repair orphaned records") {
                        let count = locationMonitor.intelligence.repairOrphanedRecords()
                        repairResult = count > 0
                            ? "Repaired \(count) record\(count == 1 ? "" : "s")"
                            : "No orphaned records found"
                    }
                    if let repairResult {
                        Text(repairResult)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Toggle("Show quality trail",
                           isOn: $locationMonitor.intelligence.showTrail)
                    Text("Draw a colored trail on the map showing quality along your route.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
                #if DEBUG
                Text("\(version) (debug)")
                #else
                Text(version)
                #endif
            }

            #if !DEBUG
            Button("Check for Updates") {
                updateChecker.checkForUpdates()
            }
            .disabled(updateChecker.isChecking)

            if updateChecker.updateAvailable, let version = updateChecker.latestVersion {
                HStack {
                    Text("v\(version) available")
                        .font(.caption)
                        .foregroundColor(.orange)
                    if let url = updateChecker.releaseURL {
                        Link("View", destination: url)
                            .font(.caption)
                    }
                }
            }
            #endif
        }
    }
}
#endif
