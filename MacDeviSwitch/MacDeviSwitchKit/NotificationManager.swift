import Foundation
import UserNotifications
import os.log

/// Manages system notifications for audio device switching events.
///
/// This class is responsible for requesting notification permissions and sending notifications to the user.
public final class NotificationManager: NotificationManaging {
    /// The logger instance for logging events and errors.
    private let logger = Logger(subsystem: "com.yourcompany.macdeviswitchkit", category: "NotificationManager")
    
    /// The user notification center instance for managing notifications.
    private let notificationCenter = UNUserNotificationCenter.current()
    
    /// The preference manager instance for checking notification settings.
    private let preferenceManager: PreferenceManaging
    
    /// Initializes a new NotificationManager
    /// - Parameter preferenceManager: The preference manager to check notification settings
    public init(preferenceManager: PreferenceManaging) {
        self.preferenceManager = preferenceManager
        requestNotificationPermission()
        logger.debug("Initializing NotificationManager")
    }
    
    /// Requests permission to show notifications
    private func requestNotificationPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                self.logger.error("Failed to request notification permission: \(error.localizedDescription)")
            } else if granted {
                self.logger.debug("Notification permission granted")
            } else {
                self.logger.warning("Notification permission denied")
            }
        }
    }
    
    /// Sends a notification with the given title and body
    /// - Parameters:
    ///   - title: The notification title
    ///   - body: The notification body text
    public func sendNotification(title: String, body: String) {
        // Check if notifications are enabled in preferences
        guard preferenceManager.showNotifications else {
            logger.debug("Notifications disabled in preferences, skipping notification: \(title)")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        // Set higher priority for error notifications.
        if title.contains("Failed") || title.contains("Error") {
            if #available(macOS 12.0, *) {
                content.interruptionLevel = .timeSensitive
            }
        }
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                self.logger.error("Error sending notification: \(error.localizedDescription)")
            }
        }
    }
}