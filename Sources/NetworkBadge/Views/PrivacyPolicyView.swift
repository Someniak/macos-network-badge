// ---------------------------------------------------------
// PrivacyPolicyView.swift — In-app privacy policy
//
// Displays the privacy policy text within the app.
// Linked from the iOS Settings view.
// ---------------------------------------------------------

#if os(iOS)
import SwiftUI

struct PrivacyPolicyView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("Privacy Policy")
                        .font(.title.bold())

                    Text("Last updated: March 21, 2026")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                section("Overview") {
                    Text("Network Badge is a network quality monitor for travelers. It records GPS-tagged latency measurements so you can see where your connection was good or bad.")
                    Text("All data stays on your device.")
                        .bold()
                    Text("Network Badge has no servers, no cloud sync, no analytics, and no advertising.")
                }

                section("Data We Collect") {
                    bullet("GPS location — your coordinates at each measurement point")
                    bullet("Network quality — latency, connection type, success/failure")
                    bullet("WiFi name (SSID) — to identify which networks had good quality")
                    bullet("WiFi signal strength (RSSI) — when available")
                    bullet("Speed and altitude — for quality analysis and map rendering")
                }

                section("How Data Is Stored") {
                    Text("All data is stored in a local SQLite database on your device at Application Support/NetworkBadge/quality.db. Data is append-only by design.")
                }

                section("Data Sharing") {
                    Text("We never share your data with anyone.")
                        .bold()
                    bullet("No data is sent to our servers (we don't have servers)")
                    bullet("No third-party data sharing")
                    bullet("No advertising or analytics SDKs")
                    bullet("No user tracking or profiling")
                }

                section("Network Requests") {
                    bullet("HTTP latency measurements — a small GET to captive.apple.com (no personal data sent)")
                    bullet("IP geolocation (optional, off by default) — estimates location when GPS is unavailable")
                    bullet("Update checks — periodic checks to GitHub Releases (no personal data sent)")
                }

                section("Location Data") {
                    Text("Network Badge requests location permission to map quality along your route. The app may request \"Always\" permission for background recording while traveling. Change this anytime in Settings → Privacy → Location Services.")
                    Text("Location data is stored only on your device and is never transmitted.")
                }

                section("Data Export & Deletion") {
                    bullet("Export: CSV export available from the History tab")
                    bullet("Delete: Remove the app to delete all data")
                }

                section("Contact") {
                    Text("Questions? Open an issue on our GitHub repository.")
                }
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
        .font(.body)
    }
}
#endif
