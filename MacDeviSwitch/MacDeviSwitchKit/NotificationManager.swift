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
    
    /// Initialize the notification manager and request permissions.
    ///
    /// This initializer requests notification permissions and logs a debug message.
    public init() {
        requestPermissions()
        logger.debug("Initializing NotificationManager")
    }
    
    /// Request permission to send notifications.
    ///
    /// This method requests authorization for alert and sound notifications and logs the result.
    private func requestPermissions() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                self.logger.debug("Notification permissions granted")
            } else if let error = error {
                self.logger.error("Failed to request notification permissions: \(error.localizedDescription)")
            } else {
                self.logger.warning("Notification permissions denied")
            }
        }
    }
    
    /// Send a notification to the user.
    ///
    /// - Parameters:
    ///   - title: The notification title.
    ///   - body: The notification body text.
    ///
    /// This method creates a notification content instance, sets the title, body, and sound, and adds the notification request to the notification center.
    public func sendNotification(title: String, body: String) {
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