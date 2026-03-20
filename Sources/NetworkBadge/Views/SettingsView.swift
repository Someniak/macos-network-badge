// ---------------------------------------------------------
// SettingsView.swift — Settings window content
// ---------------------------------------------------------

import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {

    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject var locationMonitor: LocationMonitor
    @ObservedObject var latencyMonitor: LatencyMonitor
    @ObservedObject var updateChecker: UpdateChecker

    /// Preset poll targets. "Custom" allows free-form entry.
    private let presetTargets: [(label: String, url: String)] = [
        ("Apple  (captive.apple.com)", "http://captive.apple.com/hotspot-detect.html"),
        ("Cloudflare  (cp.cloudflare.com)", "http://cp.cloudflare.com/generate_204"),
    ]

    /// True when the current targetURL doesn't match any preset
    private var isCustomTarget: Bool {
        !presetTargets.contains { $0.url == latencyMonitor.targetURL.absoluteString }
    }

    @State private var customTargetText: String = ""
    @State private var showCustomField: Bool = false
    @State private var repairResult: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("Failed to update login item: \(error)")
                        }
                    }
                ))
                Toggle("Notifications", isOn: $notificationManager.notificationsEnabled)
                if notificationManager.notificationsEnabled {
                    Toggle("Latency degradation", isOn: $notificationManager.latencyAlertsEnabled)
                        .padding(.leading, 16)
                    Toggle("Connection lost", isOn: $notificationManager.disconnectionAlertsEnabled)
                        .padding(.leading, 16)
                    Toggle("Rough connection ahead", isOn: $notificationManager.predictionAlertsEnabled)
                        .padding(.leading, 16)
                    if notificationManager.predictionAlertsEnabled && !locationMonitor.isTrackingEnabled {
                        Text("Requires GPS tracking to be enabled.")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.leading, 16)
                    }
                }

                LabeledContent("Version") {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
                    #if DEBUG
                    Text("\(version) (debug)")
                    #else
                    Text(version)
                    #endif
                }

                #if DEBUG
                Text("Update checks disabled in debug builds")
                    .font(.caption)
                    .foregroundColor(.secondary)
                #else
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
                            Button("View") { NSWorkspace.shared.open(url) }
                                .font(.caption)
                        }
                    }
                }

                if let lastChecked = updateChecker.lastChecked {
                    Text("Last checked: \(lastChecked, style: .relative) ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                #endif
            }

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
                    Text("Use a plain HTTP URL that returns 2xx with no redirects. HTTPS adds TLS overhead and skews latency.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("GPS Tracking") {
                Toggle("Enable GPS Tracking", isOn: $locationMonitor.isTrackingEnabled)
                Text("Record your location alongside network measurements to see where your connection was good or bad on a map.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if locationMonitor.isTrackingEnabled {
                    Stepper("Record every \(Int(locationMonitor.minimumDistance)) m",
                            value: $locationMonitor.minimumDistance,
                            in: 5...500, step: 5)
                    Text("Minimum distance you must move before a new location point is recorded. Lower values give more detail but use more battery.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Stepper("Min time between records: \(Int(locationMonitor.minimumInterval)) s",
                            value: $locationMonitor.minimumInterval,
                            in: 1...120, step: 1)
                    Text("Minimum seconds between location recordings, even if you've moved far enough. Prevents excessive writes at high speed.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Stepper(
                        "Stationary slowdown: \(String(format: "%.1f", locationMonitor.stationaryMultiplier))×",
                        value: $locationMonitor.stationaryMultiplier,
                        in: 1.5...4.0,
                        step: 0.5
                    )
                    Text("When you're not moving, GPS polling slows down by this factor to save battery. 2× means half as often.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    Text("Location Intelligence")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    Stepper("Ignore readings worse than: \(Int(locationMonitor.intelligence.accuracyThreshold)) m",
                            value: $locationMonitor.intelligence.accuracyThreshold,
                            in: 200...5000, step: 200)
                    Text("GPS readings less accurate than this are discarded. Increase if indoors or in areas with poor GPS signal.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("IP geolocation fallback",
                           isOn: $locationMonitor.intelligence.ipGeolocationEnabled)
                    Text("When GPS is unavailable, estimate your location from your IP address. Less precise but works indoors.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Stepper("Fill gaps up to: \(Int(locationMonitor.intelligence.maxInterpolationGap / 60)) min",
                            value: $locationMonitor.intelligence.maxInterpolationGap,
                            in: 60...600, step: 60)
                    Text("When GPS drops out briefly, fill in missing locations by interpolating between known points. Gaps longer than this are left empty.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Repair orphaned records") {
                        let count = locationMonitor.intelligence.repairOrphanedRecords()
                        repairResult = count > 0
                            ? "Repaired \(count) record\(count == 1 ? "" : "s")"
                            : "No orphaned records found"
                    }
                    Text("Retroactively add locations to measurements that were recorded before GPS had a fix.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let repairResult {
                        Text(repairResult)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Toggle("Show quality trail",
                           isOn: $locationMonitor.intelligence.showTrail)
                    Text("Draw a colored path on the map showing your route, tinted by network quality at each point.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    Text("GPS2IP")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text("Use your iPhone as a GPS source via the GPS2IP app. Connect over Wi-Fi or USB for accurate location on Macs without GPS hardware.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("Enable GPS2IP source", isOn: $locationMonitor.gps2ip.isEnabled)

                    if locationMonitor.gps2ip.isEnabled {
                        LabeledContent {} label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach($locationMonitor.gps2ip.endpoints) { $endpoint in
                                    HStack(spacing: 6) {
                                        TextField("IP", text: $endpoint.host)
                                            .textFieldStyle(.roundedBorder)
                                        Text(":")
                                            .foregroundColor(.secondary)
                                        TextField("port", text: Binding(
                                            get: { String(endpoint.port) },
                                            set: { if let v = Int($0), (1...65535).contains(v) { endpoint.port = v } }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 72)

                                        if locationMonitor.gps2ip.activeEndpoint?.id == endpoint.id {
                                            Circle()
                                                .fill(Color.green)
                                                .frame(width: 8, height: 8)
                                                .help("Active")
                                        }

                                        Button(action: {
                                            locationMonitor.gps2ip.endpoints.removeAll { $0.id == endpoint.id }
                                        }) {
                                            Image(systemName: "minus.circle")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(locationMonitor.gps2ip.endpoints.count <= 1)
                                    }
                                }

                                Button(action: {
                                    locationMonitor.gps2ip.endpoints.append(
                                        GPS2IPEndpoint(host: "", port: 11123)
                                    )
                                }) {
                                    Label("Add endpoint", systemImage: "plus.circle")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                            }
                        }
                        Text("Enter the IP address and port shown in GPS2IP on your iPhone. Add multiple endpoints to auto-failover between devices.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(locationMonitor.gps2ip.isConnected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            if locationMonitor.gps2ip.isConnected {
                                if let active = locationMonitor.gps2ip.activeEndpoint {
                                    if let t = locationMonitor.gps2ip.lastFixAt {
                                        Text("\(active.displayLabel) · fix \(t, style: .relative) ago")
                                    } else {
                                        Text("\(active.displayLabel) · waiting for fix…")
                                    }
                                } else {
                                    Text("Waiting for fix…")
                                }
                            } else if let err = locationMonitor.gps2ip.errorMessage {
                                Text(err).foregroundColor(.secondary)
                            } else {
                                Text("Disconnected")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .frame(maxHeight: 600)
        .padding(.bottom, 8)
    }
}
