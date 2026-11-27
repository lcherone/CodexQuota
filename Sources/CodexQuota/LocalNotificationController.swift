import AppKit
import CodexQuotaCore
import CodexQuotaModel
import Foundation
import UserNotifications

@MainActor
final class LocalNotificationController: NSObject, LocalNotificationControlling, UNUserNotificationCenterDelegate {
    private(set) var permission: LocalNotificationPermission = .unknown
    private let center: UNUserNotificationCenter

    override init() {
        center = .current()
        super.init()
        center.delegate = self
    }

    public func refreshPermission() async {
        permission = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: Self.permission(for: settings.authorizationStatus))
            }
        }
    }

    public func requestPermission() async -> Bool {
        do {
            let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
            await refreshPermission()
            return granted && permission == .authorized
        } catch {
            permission = .unavailable
            return false
        }
    }

    public func openNotificationSettings() {
        let settingsPath = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        if let bundleIdentifier = Bundle.main.bundleIdentifier,
           let appSettingsURL = URL(string: "\(settingsPath)?id=\(bundleIdentifier)"),
           NSWorkspace.shared.open(appSettingsURL) {
            return
        }
        if let notificationSettingsURL = URL(string: settingsPath) {
            NSWorkspace.shared.open(notificationSettingsURL)
        }
    }

    public func deliver(accountLabel: String, event: QuotaAlertEvent) async -> Bool {
        await refreshPermission()
        guard permission == .authorized else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Codex quota"
        content.body = Self.message(accountLabel: accountLabel, event: event)
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                center.add(request) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            return true
        } catch {
            await refreshPermission()
            return false
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated private static func permission(for status: UNAuthorizationStatus) -> LocalNotificationPermission {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .authorized
        @unknown default: .unavailable
        }
    }

    private static func message(accountLabel: String, event: QuotaAlertEvent) -> String {
        switch event {
        case let .weeklyThreshold(threshold):
            "\(accountLabel) crossed \(threshold)% of its weekly allowance."
        case .ahead:
            "\(accountLabel) is ahead of the current quota slice."
        case .reached:
            "\(accountLabel) has reached its reported allowance."
        }
    }
}
