// ---------------------------------------------------------
// NotificationManager.swift — Quality drop notifications
//
// Sends macOS notifications when network quality degrades.
// Essential for train travel — you get alerted when the
// connection gets bad so you can save your work or switch
// to a hotspot.
//
// Features:
//   - Only fires on quality *degradation* (not steady-state)
//   - Rate-limited to avoid notification spam (30s cooldown)
//   - User can toggle notifications on/off in settings
// ---------------------------------------------------------

import Foundation
import UserNotifications
import Combine

/// Manages macOS notifications for network quality changes.
///
/// Usage:
///   let manager = NotificationManager()
///   manager.requestPermission()
///   manager.notifyQualityDrop(from: .good, to: .poor, latencyMs: 245)
///
final class NotificationManager: ObservableObject {

    // MARK: - Published Properties

    /// Whether notifications are enabled (persisted in UserDefaults)
    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Self.enabledKey)
        }
    }

    // MARK: - Private Properties

    /// UserDefaults key for the enabled toggle
    private static let enabledKey = "notificationsEnabled"

    /// Minimum time between notifications (prevents spam)
    let cooldownInterval: TimeInterval

    /// When the last notification was sent
    private(set) var lastNotificationDate: Date? = nil

    /// The notification center we use to deliver notifications
    private let notificationCenter: UNUserNotificationCenter

    // MARK: - Initialization

    /// Creates a new NotificationManager.
    ///
    /// - Parameters:
    ///   - cooldown: Minimum seconds between notifications (default: 30)
    ///   - center: The notification center to use (injectable for testing)
    init(
        cooldown: TimeInterval = 30.0,
        center: UNUserNotificationCenter = .current()
    ) {
        self.cooldownInterval = cooldown
        self.notificationCenter = center
        // Load persisted preference (defaults to true)
        self.notificationsEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    // MARK: - Permission

    /// Request notification permission from the user.
    /// Call this once at app startup. macOS will show a system dialog
    /// the first time, then remember the user's choice.
    func requestPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    // MARK: - Quality Drop Detection

    /// Sends a notification if quality has degraded.
    ///
    /// Only fires when:
    ///   1. Notifications are enabled
    ///   2. Quality has gotten *worse* (not same or better)
    ///   3. New quality is .poor or .bad
    ///   4. At least `cooldownInterval` seconds since last notification
    ///
    /// - Parameters:
    ///   - oldQuality: The previous quality level
    ///   - newQuality: The new (worse) quality level
    ///   - latencyMs: Current latency for the notification body
    func notifyQualityDrop(
        from oldQuality: LatencyQuality,
        to newQuality: LatencyQuality,
        latencyMs: Double
    ) {
        // Check if notifications are enabled
        guard notificationsEnabled else { return }

        // Only alert on poor or bad quality
        guard newQuality == .poor || newQuality == .bad else { return }

        // Only fire on degradation (new is worse than old)
        guard isDegradation(from: oldQuality, to: newQuality) else { return }

        // Rate limit: don't spam
        if let lastDate = lastNotificationDate {
            let elapsed = Date().timeIntervalSince(lastDate)
            if elapsed < cooldownInterval {
                return
            }
        }

        // Send the notification
        sendNotification(quality: newQuality, latencyMs: latencyMs)
        lastNotificationDate = Date()
    }

    // MARK: - Helpers

    /// Returns true if the quality transition represents a degradation.
    /// Uses numeric ordering: excellent=0, good=1, ..., bad=4
    func isDegradation(from oldQuality: LatencyQuality, to newQuality: LatencyQuality) -> Bool {
        return severityIndex(newQuality) > severityIndex(oldQuality)
    }

    /// Maps quality to a numeric severity (higher = worse)
    private func severityIndex(_ quality: LatencyQuality) -> Int {
        switch quality {
        case .excellent: return 0
        case .good:      return 1
        case .fair:      return 2
        case .poor:      return 3
        case .bad:       return 4
        case .unknown:   return -1  // unknown doesn't trigger alerts
        }
    }

    /// Actually deliver the notification via UNUserNotificationCenter
    private func sendNotification(quality: LatencyQuality, latencyMs: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Network Quality Dropped"
        content.body = "Latency is now \(Int(latencyMs))ms (\(quality.rawValue))"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "quality-drop-\(UUID().uuidString)",
            content: content,
            trigger: nil  // deliver immediately
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to deliver notification: \(error)")
            }
        }
    }
}
