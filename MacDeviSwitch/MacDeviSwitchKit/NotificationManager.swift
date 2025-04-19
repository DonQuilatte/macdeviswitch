import Foundation
import UserNotifications
import os.log

/// Errors that can occur during notification operations
public enum NotificationManagerError: Error, LocalizedError {
    case permissionDenied
    case notificationFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notification permission was denied by the user"
        case .notificationFailed(let error):
            return "Failed to send notification: \(error.localizedDescription)"
        }
    }
}

/// Handles user notifications for audio device switching events.
///
/// This class is responsible for requesting notification permissions and sending notifications to the user.
public final class NotificationManager: NotificationManaging {
    /// The logger instance for logging events and errors.
    private let logger = Logger(subsystem: "via.MacDeviSwitch.kit", category: "NotificationManager")

    /// The user notification center instance for managing notifications.
    private let notificationCenter = UNUserNotificationCenter.current()

    /// The preference manager instance for checking notification settings.
    private let preferenceManager: PreferenceManaging

    /// Whether notification permissions have been granted
    private var notificationsAuthorized = false

    /// Initializes a new NotificationManager
    /// - Parameter preferenceManager: The preference manager to check notification settings
    ///
    /// Creates a new instance of the NotificationManager class, responsible for handling user notifications.
    public init(preferenceManager: PreferenceManaging) {
        self.preferenceManager = preferenceManager
        logger.debug("Initializing NotificationManager")
        checkNotificationPermission()
    }

    /// Checks current notification permission status
    private func checkNotificationPermission() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            guard let self = self else { return }

            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.notificationsAuthorized = true
                self.logger.debug("Notification permission is already granted")
            case .denied:
                self.notificationsAuthorized = false
                self.logger.warning("Notification permission is denied")
            case .notDetermined:
                self.requestNotificationPermission()
            case .ephemeral:
                self.notificationsAuthorized = true
                self.logger.debug("Notification permission is ephemeral")
            @unknown default:
                self.notificationsAuthorized = false
                self.logger.warning("Unknown notification authorization status")
            }
        }
    }

    /// Requests permission to show notifications
    private func requestNotificationPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error(
                    "Failed to request notification permission: \(error.localizedDescription)"
                )
                self.notificationsAuthorized = false
            } else if granted {
                self.logger.debug("Notification permission granted")
                self.notificationsAuthorized = true
            } else {
                self.logger.warning("Notification permission denied")
                self.notificationsAuthorized = false
            }
        }
    }

    /// Sends a notification to the user.
    /// - Parameters:
    ///   - title: The notification title.
    ///   - body: The notification body.
    ///
    /// Sends a notification with the given title and body to the user, if notification permissions are granted and notifications are enabled in preferences.
    public func sendNotification(title: String, body: String) {
        // Check if notifications are enabled in preferences
        guard preferenceManager.showNotifications else {
            logger.debug("Notifications disabled in preferences, skipping notification: \(title)")
            return
        }

        // Check if we have permission to send notifications
        guard notificationsAuthorized else {
            logger.warning("Cannot send notification: permission not granted")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default

        // Create a request with a unique identifier
        let identifier = "via.MacDeviSwitch.\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        // Add the request to the notification center
        UserNotifications.UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                let errorMessage = "Error scheduling notification: \(error.localizedDescription)"
                self?.logger.error("\(errorMessage, privacy: .public)")
            } else {
                let baseMessage = "Notification scheduled successfully"
                let identifierInfo = "with identifier: \(identifier)"
                self?.logger.info("\(baseMessage) \(identifierInfo, privacy: .public)")
            }
        }
    }
}
