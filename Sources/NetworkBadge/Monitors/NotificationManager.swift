// ---------------------------------------------------------
// NotificationManager.swift — Network alert notifications
//
// Sends macOS notifications when network quality degrades
// or when a connection is lost entirely.
// Essential for train travel — you get alerted when the
// connection gets bad so you can save your work or switch
// to a hotspot.
//
// Features:
//   - Fires on quality *degradation* (not steady-state)
//   - Fires on connection loss (WiFi/Ethernet/tethering dropped)
//   - Rate-limited to avoid notification spam (30s cooldown)
//   - User can toggle notifications on/off in settings
// ---------------------------------------------------------

import Foundation
import UserNotifications
import Combine

// MARK: - Network Alert

/// Categorizes the different types of network alerts.
enum NetworkAlert {
    /// A primary connection method was lost (WiFi, Ethernet, tethering, etc.)
    case connectionLost(ConnectionType)
    /// Network quality degraded to poor or bad
    case latencyDegraded(LatencyQuality, Double)
    /// Spatial lookahead predicts poor/bad connectivity ahead
    case poorConnectivityAhead(QualityPrediction)

    /// Notification title for this alert type
    var title: String {
        switch self {
        case .connectionLost:
            return "Connection Lost"
        case .latencyDegraded:
            return "Network Quality Dropped"
        case .poorConnectivityAhead:
            return "Rough Connection Ahead"
        }
    }

    /// Notification body for this alert type
    var body: String {
        switch self {
        case .connectionLost(let connectionType):
            return "\(connectionType.rawValue) disconnected"
        case .latencyDegraded(let quality, let latencyMs):
            if latencyMs == 0 {
                return "Connection timed out (\(quality.rawValue.lowercased()))"
            }
            return "Latency is now \(Int(latencyMs))ms (\(quality.rawValue.lowercased()))"
        case .poorConnectivityAhead(let prediction):
            let minutes = Int(prediction.minutesAhead)
            return "Expect \(prediction.expectedQuality.rawValue.lowercased()) connectivity in ~\(minutes) min (~\(Int(prediction.averageLatencyMs))ms avg, \(prediction.sampleCount) samples)"
        }
    }

    /// Notification identifier prefix for this alert type
    var identifierPrefix: String {
        switch self {
        case .connectionLost:
            return "connection-lost"
        case .latencyDegraded:
            return "quality-drop"
        case .poorConnectivityAhead:
            return "prediction-ahead"
        }
    }
}

/// Manages macOS notifications for network quality changes.
///
/// Usage:
///   let manager = NotificationManager()
///   manager.requestPermission()
///   manager.notifyQualityDrop(to: .poor, latencyMs: 245)
///
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    // MARK: - Published Properties

    /// Master toggle — disables all notifications when off (persisted)
    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Self.enabledKey)
        }
    }

    /// Per-type toggle: latency degradation alerts (persisted)
    @Published var latencyAlertsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(latencyAlertsEnabled, forKey: Self.latencyKey)
        }
    }

    /// Per-type toggle: connection loss alerts (persisted)
    @Published var disconnectionAlertsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(disconnectionAlertsEnabled, forKey: Self.disconnectionKey)
        }
    }

    /// Per-type toggle: predictive "rough connection ahead" alerts (persisted)
    @Published var predictionAlertsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(predictionAlertsEnabled, forKey: Self.predictionKey)
        }
    }

    // MARK: - Private Properties

    /// UserDefaults keys
    private static let enabledKey = "notificationsEnabled"
    private static let latencyKey = "latencyAlertsEnabled"
    private static let disconnectionKey = "disconnectionAlertsEnabled"
    private static let predictionKey = "predictionAlertsEnabled"

    /// Minimum time between notifications (prevents spam)
    let cooldownInterval: TimeInterval

    /// When the last notification was sent
    private(set) var lastNotificationDate: Date? = nil

    /// The last observed quality level (used to detect degradation)
    private var previousQuality: LatencyQuality = .unknown

    /// The last observed connection type (used to detect disconnection)
    private(set) var previousConnectionType: ConnectionType = .unknown

    /// Whether we've already alerted for the current prediction (reset when prediction clears)
    private(set) var hasAlertedForCurrentPrediction: Bool = false

    /// Connection types that represent a real, usable network connection.
    /// Only transitions FROM these types to `.disconnected` trigger alerts.
    static let primaryConnectionTypes: Set<ConnectionType> = [
        .wifi, .ethernet, .usbTethering, .hotspot, .cellular
    ]

    /// Returns the notification center only when running as a real .app bundle.
    /// UNUserNotificationCenter crashes in CLI (`swift run`) and test runner
    /// environments, even when a bundleIdentifier exists.
    private var notificationCenter: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundleURL.pathExtension == "app" else {
            return nil
        }
        return .current()
    }

    // MARK: - Initialization

    init(cooldown: TimeInterval = 30.0) {
        self.cooldownInterval = cooldown
        self.notificationsEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        self.latencyAlertsEnabled = UserDefaults.standard.object(forKey: Self.latencyKey) as? Bool ?? true
        self.disconnectionAlertsEnabled = UserDefaults.standard.object(forKey: Self.disconnectionKey) as? Bool ?? true
        self.predictionAlertsEnabled = UserDefaults.standard.object(forKey: Self.predictionKey) as? Bool ?? true
        super.init()
    }

    // MARK: - Permission

    /// Request notification permission from the user.
    /// Call this once at app startup. macOS will show a system dialog
    /// the first time, then remember the user's choice.
    func requestPermission() {
        guard let center = notificationCenter else { return }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Allow notifications to display as banners even when the app is in the foreground.
    /// Without this, macOS silently suppresses notifications for the active app —
    /// and menu bar apps are always considered "active".
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
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
    ///   - newQuality: The new quality level
    ///   - latencyMs: Current latency for the notification body
    func notifyQualityDrop(
        to newQuality: LatencyQuality,
        latencyMs: Double
    ) {
        defer { previousQuality = newQuality }

        // Check if notifications are enabled
        guard notificationsEnabled, latencyAlertsEnabled else { return }

        // Only alert on poor or bad quality
        guard newQuality == .poor || newQuality == .bad else { return }

        // Only fire on degradation (new is worse than old)
        guard isDegradation(from: previousQuality, to: newQuality) else { return }

        // Rate limit: don't spam
        guard !isCooldownActive() else { return }

        // Send the notification
        sendNotification(alert: .latencyDegraded(newQuality, latencyMs))
        lastNotificationDate = Date()
    }

    // MARK: - Connection Loss Detection

    /// Sends a notification when a primary connection is lost.
    ///
    /// Only fires when:
    ///   1. Notifications are enabled
    ///   2. Previous connection was a primary type (WiFi, Ethernet, etc.)
    ///   3. New connection is `.disconnected`
    ///   4. At least `cooldownInterval` seconds since last notification
    ///
    /// - Parameter newType: The new connection type
    func notifyConnectionChange(to newType: ConnectionType) {
        let oldType = previousConnectionType
        previousConnectionType = newType

        guard notificationsEnabled, disconnectionAlertsEnabled else { return }

        // Only alert when transitioning from a primary connection to disconnected
        guard newType == .disconnected else { return }
        guard Self.primaryConnectionTypes.contains(oldType) else { return }

        // Rate limit: don't spam
        guard !isCooldownActive() else { return }

        sendNotification(alert: .connectionLost(oldType))
        lastNotificationDate = Date()
    }

    // MARK: - Predictive Alerts

    /// Sends a notification when the spatial lookahead predicts poor/bad connectivity ahead.
    ///
    /// Only fires when:
    ///   1. Notifications are enabled
    ///   2. Prediction quality is `.poor` or `.bad`
    ///   3. Confidence is at least 0.5 (5+ historical samples)
    ///   4. Haven't already alerted for this prediction window
    ///   5. At least `cooldownInterval` seconds since last notification
    ///
    /// - Parameter prediction: The new lookahead prediction, or nil if cleared
    func notifyPredictionChange(to prediction: QualityPrediction?) {
        guard let prediction = prediction else {
            // Prediction cleared — reset so we can alert again next time
            hasAlertedForCurrentPrediction = false
            return
        }

        guard notificationsEnabled, predictionAlertsEnabled else { return }
        guard prediction.expectedQuality == .poor || prediction.expectedQuality == .bad else {
            hasAlertedForCurrentPrediction = false
            return
        }
        guard prediction.confidence >= 0.5 else { return }
        guard !hasAlertedForCurrentPrediction else { return }
        guard !isCooldownActive() else { return }

        sendNotification(alert: .poorConnectivityAhead(prediction))
        lastNotificationDate = Date()
        hasAlertedForCurrentPrediction = true
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

    /// Returns true if we're still within the cooldown period since the last notification
    private func isCooldownActive() -> Bool {
        guard let lastDate = lastNotificationDate else { return false }
        return Date().timeIntervalSince(lastDate) < cooldownInterval
    }

    /// Deliver a notification via UNUserNotificationCenter
    private func sendNotification(alert: NetworkAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(alert.identifierPrefix)-\(UUID().uuidString)",
            content: content,
            trigger: nil  // deliver immediately
        )

        notificationCenter?.add(request) { error in
            if let error = error {
                print("Failed to deliver notification: \(error)")
            }
        }
    }
}
