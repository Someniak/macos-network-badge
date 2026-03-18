// ---------------------------------------------------------
// SettingsView.swift — Settings window content
// ---------------------------------------------------------

import ServiceManagement
import SwiftUI

struct SettingsView: View {

    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject var locationMonitor: LocationMonitor
    @ObservedObject var latencyMonitor: LatencyMonitor

    /// Preset poll targets. "Custom" allows free-form entry.
    private let presetTargets: [(label: String, url: String)] = [
        ("Apple  (captive.apple.com)", "http://captive.apple.com/hotspot-detect.html"),
        ("Cloudflare  (1.1.1.1)",      "http://1.1.1.1"),
        ("Google  (google.com)",        "http://google.com"),
    ]

    /// True when the current targetURL doesn't match any preset
    private var isCustomTarget: Bool {
        !presetTargets.contains { $0.url == latencyMonitor.targetURL.absoluteString }
    }

    @State private var customTargetText: String = ""
    @State private var showCustomField: Bool = false

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
                Toggle("Alert on Poor Connection", isOn: $notificationManager.notificationsEnabled)
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
                }
            }

            Section("GPS Tracking") {
                Toggle("Enable GPS Tracking", isOn: $locationMonitor.isTrackingEnabled)

                if locationMonitor.isTrackingEnabled {
                    Stepper("Record every \(Int(locationMonitor.minimumDistance)) m",
                            value: $locationMonitor.minimumDistance,
                            in: 10...500, step: 10)
                    Stepper("Min gap: \(Int(locationMonitor.minimumInterval)) s",
                            value: $locationMonitor.minimumInterval,
                            in: 5...120, step: 5)
                    Stepper(
                        "Backoff: \(String(format: "%.1f", locationMonitor.stationaryMultiplier))×",
                        value: $locationMonitor.stationaryMultiplier,
                        in: 1.5...4.0,
                        step: 0.5
                    )

                    Divider()

                    Text("Location Intelligence")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    Stepper("Max accuracy: \(Int(locationMonitor.intelligence.accuracyThreshold)) m",
                            value: $locationMonitor.intelligence.accuracyThreshold,
                            in: 200...5000, step: 200)

                    Toggle("IP geolocation fallback",
                           isOn: $locationMonitor.intelligence.ipGeolocationEnabled)

                    Stepper("Interpolation gap: \(Int(locationMonitor.intelligence.maxInterpolationGap / 60)) min",
                            value: $locationMonitor.intelligence.maxInterpolationGap,
                            in: 60...600, step: 60)

                    Toggle("Show quality trail",
                           isOn: $locationMonitor.intelligence.showTrail)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .padding(.bottom, 8)
    }
}
