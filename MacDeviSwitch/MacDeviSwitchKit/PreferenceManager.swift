import Foundation
import os.log

public protocol PreferenceManaging {
    var targetMicrophoneUID: String? { get set }
    var revertOnLidOpen: Bool { get set }
}

public final class PreferenceManager: PreferenceManaging {
    private let logger = Logger(subsystem: "com.yourcompany.macdeviswitchkit", category: "PreferenceManager") // Replace
    private let userDefaults: UserDefaults

    // Define keys for UserDefaults
    private enum Keys {
        static let targetMicrophoneUID = "targetMicrophoneUID"
        static let revertOnLidOpen = "revertOnLidOpen"
    }

    // Allow injecting UserDefaults for testing
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        logger.debug("Initializing PreferenceManager")
        // Register default values if they don't exist
        registerDefaults()
    }

    private func registerDefaults() {
        userDefaults.register(defaults: [
            Keys.revertOnLidOpen: true // Default to reverting on lid open
            // No default for targetMicrophoneUID, it should be explicitly set by the user
        ])
        logger.debug("Registered default preferences.")
    }

    public var targetMicrophoneUID: String? {
        get {
            let uid = userDefaults.string(forKey: Keys.targetMicrophoneUID)
            logger.debug("Getting targetMicrophoneUID: \(uid ?? "nil")")
            return uid
        }
        set {
            logger.info("Setting targetMicrophoneUID to: \(newValue ?? "nil")")
            userDefaults.set(newValue, forKey: Keys.targetMicrophoneUID)
        }
    }

    public var revertOnLidOpen: Bool {
        get {
            let shouldRevert = userDefaults.bool(forKey: Keys.revertOnLidOpen)
            logger.debug("Getting revertOnLidOpen: \(shouldRevert)")
            return shouldRevert
        }
        set {
            logger.info("Setting revertOnLidOpen to: \(newValue)")
            userDefaults.set(newValue, forKey: Keys.revertOnLidOpen)
        }
    }
}
