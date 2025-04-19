import Foundation
import CoreAudio
import os.log

// Forward declare AudioDeviceInfo and AudioSwitching as actual protocol and struct signatures for typechecking
// Forward declare AudioSwitcherError for protocol typechecking
public enum AudioSwitcherError: Error, LocalizedError {
    case deviceNotFound(uid: String)
    case deviceIDNotFound
    case switchFailed(deviceID: AudioDeviceID, status: OSStatus)
    case propertyAccessFailed(selector: AudioObjectPropertySelector, status: OSStatus)
    public var errorDescription: String? {
        switch self {
        case .deviceNotFound(let uid):
            return "Audio device with UID '\(uid)' not found"
        case .deviceIDNotFound:
            return "Could not retrieve default audio device ID"
        case .switchFailed(let deviceID, let status):
            return "Failed to set device \(deviceID) as default (Error: \(status))"
        case .propertyAccessFailed(let selector, let status):
            return "Failed to access audio property \(selector) (Error: \(status))"
        }
    }
}

public struct AudioDeviceInfo: Identifiable, Hashable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let isInput: Bool
    public let isOutput: Bool
    public init(id: AudioDeviceID, uid: String, name: String, isInput: Bool, isOutput: Bool = false) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isInput = isInput
        self.isOutput = isOutput
    }
}

public protocol AudioSwitching {
    func setDefaultInputDevice(uid: String) -> Result<Void, AudioSwitcherError>
    func setDefaultInputDevice(deviceID: AudioDeviceID) -> Result<Void, AudioSwitcherError>
    func getDefaultInputDeviceID() -> Result<AudioDeviceID, AudioSwitcherError>
}

/// Protocol for notification management.
/// Handles user notifications for audio device switching events.
///
/// Implement this protocol to provide a custom notification manager.
public protocol NotificationManaging {
    /// Send a notification to the user.
    /// - Parameters:
    ///   - title: The notification title.
    ///   - body: The notification body text.
    func sendNotification(title: String, body: String)
}

/// Protocol for lid state monitoring.
/// Monitors the laptop lid state (open/closed).
///
/// Implement this protocol to provide a custom lid state monitor.
public protocol LidStateMonitoring {
    /// Current lid state (true if open, false if closed).
    var isLidOpen: Bool { get }

    /// Callback triggered when lid state changes.
    /// - Parameter: Boolean indicating if lid is open (true) or closed (false).
    var onLidStateChange: ((Bool) -> Void)? { get set }

    /// Start monitoring lid state changes.
    /// - Throws: LidStateMonitorError if monitoring cannot be started.
    func startMonitoring() throws

    /// Stop monitoring lid state changes.
    func stopMonitoring()
}

/// Protocol for display monitoring.
/// Monitors external display connections.
///
/// Implement this protocol to provide a custom display monitor.
public protocol DisplayMonitoring {
    /// Current external display connection state.
    var isExternalDisplayConnected: Bool { get }

    /// Callback triggered when display connection changes.
    /// - Parameter: Boolean indicating if external display is connected.
    var onDisplayConnectionChange: ((Bool) -> Void)? { get set }

    /// Start monitoring display connection changes.
    func startMonitoring()

    /// Stop monitoring display connection changes.
    func stopMonitoring()
}

/// Protocol for audio device monitoring.
/// Monitors available audio input devices.
///
/// Implement this protocol to provide a custom audio device monitor.
public protocol AudioDeviceMonitoring {
    /// List of currently available audio input devices.
    var availableInputDevices: [AudioDeviceInfo] { get }

    /// Start monitoring audio device changes.
    func startMonitoring()

    /// Stop monitoring audio device changes.
    func stopMonitoring()
}

/// Protocol for preference management.
/// Manages user preferences for audio device switching.
///
/// Implement this protocol to provide a custom preference manager.
public protocol PreferenceManaging {
    /// The UID of the target microphone to switch to.
    var targetMicrophoneUID: String? { get set }

    /// Whether to revert to the fallback microphone on lid open.
    var revertToFallbackOnLidOpen: Bool { get set }

    /// Whether to show notifications for audio device switching events.
    var showNotifications: Bool { get set }
}

/// Protocol for the switch controller.
/// Controls audio device switching based on lid state and display connections.
///
/// Implement this protocol to provide a custom switch controller.
public protocol SwitchControlling {
    /// Start the controller and perform initial evaluation.
    /// - Throws: SwitchControllerError if an error occurs during startup.
    func start() throws

    /// Evaluate current conditions and switch audio devices if necessary.
    /// - Returns: Boolean indicating if a switch occurred.
    /// - Throws: SwitchControllerError if an error occurs during evaluation and switching.
    func evaluateAndSwitch() throws -> Bool

    /// Start monitoring all relevant state changes.
    /// - Throws: SwitchControllerError if an error occurs during monitoring.
    func startMonitoring() throws

    /// Stop monitoring all state changes.
    func stopMonitoring()

    /// Set the notification manager.
    /// - Parameter notificationManager: Manager for user notifications.
    func setNotificationManager(_ notificationManager: NotificationManaging)
}
