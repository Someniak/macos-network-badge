// ---------------------------------------------------------
// UpdateChecker.swift — Checks GitHub Releases for updates
//
// Periodically queries the GitHub API for the latest release
// and compares it against the running app's version.
// Disabled in debug builds to avoid noise during development.
// ---------------------------------------------------------

import Foundation

final class UpdateChecker: ObservableObject {

    @Published var latestVersion: String?
    @Published var updateAvailable: Bool = false
    @Published var releaseURL: URL?
    @Published var lastChecked: Date?
    @Published var isChecking: Bool = false

    private var timer: Timer?
    private static let checkInterval: TimeInterval = 6 * 60 * 60 // 6 hours
    // The /releases/latest endpoint already excludes prereleases and drafts
    private static let apiURL = URL(string: "https://api.github.com/repos/Someniak/macos-network-badge/releases/latest")!

    init() {
        // Delay the first check by 5 seconds so the app finishes launching
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.checkForUpdates()
            self?.startTimer()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func checkForUpdates() {
        #if DEBUG
        // No-op in debug builds
        return
        #else
        guard !isChecking else { return }
        isChecking = true

        var request = URLRequest(url: Self.apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false
                self.lastChecked = Date()

                guard let data, error == nil,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String,
                      let htmlURL = json["html_url"] as? String,
                      json["prerelease"] as? Bool != true,
                      json["draft"] as? Bool != true
                else { return }

                let remote = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                self.latestVersion = remote
                self.releaseURL = URL(string: htmlURL)

                let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
                self.updateAvailable = Self.isNewer(remote: remote, local: current)
            }
        }.resume()
        #endif
    }

    // MARK: - Private

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
    }

    /// Returns true when `remote` is a newer semantic version than `local`.
    static func isNewer(remote: String, local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}
