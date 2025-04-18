import Foundation
import CoreAudio

/// Protocol for notification management
/// Handles user notifications for audio device switching events
public protocol NotificationManaging {
    /// Send a notification to the user
    /// - Parameters:
    ///   - title: The notification title
    ///   - body: The notification body text
    func sendNotification(title: String, body: String)
}

/// Protocol for lid state monitoring
/// Monitors the laptop lid state (open/closed)
public protocol LidStateMonitoring {
    /// Current lid state (true if open, false if closed)
    var isLidOpen: Bool { get }
    
    /// Callback triggered when lid state changes
    /// - Parameter: Boolean indicating if lid is open (true) or closed (false)
    var onLidStateChange: ((Bool) -> Void)? { get set }
    
    /// Start monitoring lid state changes
    func startMonitoring()
    
    /// Stop monitoring lid state changes
    func stopMonitoring()
}

/// Protocol for display monitoring
/// Monitors external display connections
public protocol DisplayMonitoring {
    /// Current external display connection state
    var isExternalDisplayConnected: Bool { get }
    
    /// Callback triggered when display connection changes
    /// - Parameter: Boolean indicating if external display is connected
    var onDisplayConnectionChange: ((Bool) -> Void)? { get set }
    
    /// Start monitoring display connection changes
    func startMonitoring()
    
    /// Stop monitoring display connection changes
    func stopMonitoring()
}

/// Protocol for audio device monitoring
/// Monitors available audio input devices
public protocol AudioDeviceMonitoring {
    /// List of currently available audio input devices
    var availableInputDevices: [AudioDeviceInfo] { get }
    
    /// Start monitoring audio device changes
    func startMonitoring()
    
    /// Stop monitoring audio device changes
    func stopMonitoring()
}

/// Protocol for the switch controller
/// Controls audio device switching based on lid state and display connections
public protocol SwitchControlling {
    /// Start the controller and perform initial evaluation
    func start()
    
    /// Evaluate current conditions and switch audio devices if necessary
    /// - Returns: Boolean indicating if a switch occurred
    func evaluateAndSwitch() -> Bool
    
    /// Start monitoring all relevant state changes
    func startMonitoring()
    
    /// Stop monitoring all state changes
    func stopMonitoring()
}