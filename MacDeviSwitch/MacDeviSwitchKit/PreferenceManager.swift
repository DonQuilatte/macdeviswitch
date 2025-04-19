import Foundation
import os.log

/// Errors that can occur during preference management
public enum PreferenceManagerError: Error, LocalizedError {
    case invalidPreferenceValue(key: String, value: Any?)
    case storageFailure(key: String)

    public var errorDescription: String? {
        switch self {
        case .invalidPreferenceValue(let key, let value):
            return "Invalid preference value for key '\(key)': \(String(describing: value))"
        case .storageFailure(let key):
            return "Failed to store preference value for key '\(key)'"
        }
    }
}

/// Manages user preferences for MacDeviSwitch.
public final class PreferenceManager: PreferenceManaging {
    private let logger = Logger(subsystem: "via.MacDeviSwitch.kit", category: "PreferenceManager")
    private let userDefaults: UserDefaults

    // Define keys for UserDefaults
    private enum Keys {
        static let targetMicrophoneUID = "targetMicrophoneUID"
        static let revertToFallbackOnLidOpen = "revertToFallbackOnLidOpen"
        static let showNotifications = "showNotifications"
    }

    /// Initializes a new instance of the PreferenceManager.
    ///
    /// - Parameter userDefaults: The UserDefaults instance to use for storing preferences. Defaults to .standard.
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        logger.debug("Initializing PreferenceManager")
        // Register default values if they don't exist
        registerDefaults()
    }

    private func registerDefaults() {
        userDefaults.register(defaults: [
            Keys.revertToFallbackOnLidOpen: true, // Default to reverting on lid open
            Keys.showNotifications: true // Default to showing notifications
            // No default for targetMicrophoneUID - this must be explicitly set by the user
        ])
    }

    // MARK: - PreferenceManaging Protocol

    /// The UID of the user's target microphone.
    public var targetMicrophoneUID: String? {
        get {
            let uid = userDefaults.string(forKey: Keys.targetMicrophoneUID)
            logger.debug("Retrieved targetMicrophoneUID: \(uid ?? "nil")")
            return uid
        }
        set {
            logger.debug("Setting targetMicrophoneUID to: \(newValue ?? "nil")")
            userDefaults.set(newValue, forKey: Keys.targetMicrophoneUID)
        }
    }

    /// Whether to revert to fallback microphone when lid is opened.
    public var revertToFallbackOnLidOpen: Bool {
        get {
            let value = userDefaults.bool(forKey: Keys.revertToFallbackOnLidOpen)
            logger.debug("Retrieved revertToFallbackOnLidOpen: \(value)")
            return value
        }
        set {
            logger.debug("Setting revertToFallbackOnLidOpen to: \(newValue)")
            userDefaults.set(newValue, forKey: Keys.revertToFallbackOnLidOpen)
        }
    }

    /// Whether to show notifications to the user.
    public var showNotifications: Bool {
        get {
            let showNotifications = userDefaults.bool(forKey: Keys.showNotifications)
            logger.debug("Getting showNotifications: \(showNotifications)")
            return showNotifications
        }
        set {
            logger.info("Setting showNotifications to: \(newValue)")
            userDefaults.set(newValue, forKey: Keys.showNotifications)
        }
    }
}
