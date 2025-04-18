import Foundation
import CoreAudio
import os.log

// MARK: - Error Types

/// Errors that can occur during switch controller operations
public enum SwitchControllerError: LocalizedError {
    case monitoringFailure(String)
    case audioSwitchingFailure(String)
    
    public var errorDescription: String? {
        switch self {
        case .monitoringFailure(let message):
            return "Monitoring failure: \(message)"
        case .audioSwitchingFailure(let message):
            return "Audio switching failure: \(message)"
        }
    }
}

/// Controller for audio device switching based on lid state and display connections
public class SwitchController: SwitchControlling {
    // MARK: - Properties
    
    /// Logger for SwitchController events.
    private let logger = Logger(subsystem: "via.MacDeviSwitch.kit", category: "SwitchController")
    
    /// Monitor for lid state changes.
    /// 
    /// This dependency is used to track changes in the lid state, which can trigger audio device switching.
    private var lidMonitor: LidStateMonitoring
    
    /// Monitor for display connection changes.
    /// 
    /// This dependency is used to track changes in display connections, which can trigger audio device switching.
    private var displayMonitor: DisplayMonitoring
    
    /// Monitor for audio device changes.
    /// 
    /// This dependency is used to track changes in available audio devices, which can affect audio device switching.
    private let audioDeviceMonitor: AudioDeviceMonitoring
    
    /// Service for switching audio devices.
    /// 
    /// This dependency is used to perform the actual audio device switching.
    private let audioSwitcher: AudioSwitching
    
    /// User preferences.
    /// 
    /// This dependency is used to access user preferences, such as the target microphone and fallback microphone settings.
    private let preferences: PreferenceManaging
    
    /// Manager for user notifications.
    /// 
    /// This dependency is used to send notifications to the user about audio device switching events.
    private var notificationManager: NotificationManaging?
    
    /// Stores the fallback microphone CoreAudio ID for reversion.
    private var fallbackMicrophoneID: AudioDeviceID?
    /// Stores the fallback microphone UID for reversion.
    private var fallbackMicrophoneUID: String?
    
    // MARK: - Initialization
    
    /// Initialize a new switch controller.
    /// 
    /// - Parameters:
    ///   - lidMonitor: Monitor for lid state changes.
    ///   - displayMonitor: Monitor for display connection changes.
    ///   - audioDeviceMonitor: Monitor for audio device changes.
    ///   - audioSwitcher: Service for switching audio devices.
    ///   - preferences: User preferences.
    public init(
        lidMonitor: LidStateMonitoring,
        displayMonitor: DisplayMonitoring,
        audioDeviceMonitor: AudioDeviceMonitoring,
        audioSwitcher: AudioSwitching,
        preferences: PreferenceManaging
    ) {
        self.lidMonitor = lidMonitor
        self.displayMonitor = displayMonitor
        self.audioDeviceMonitor = audioDeviceMonitor
        self.audioSwitcher = audioSwitcher
        self.preferences = preferences
        
        logger.debug("SwitchController initialized")
    }
    
    /// Set the notification manager.
    /// 
    /// - Parameter notificationManager: Manager for user notifications.
    public func setNotificationManager(_ notificationManager: NotificationManaging) {
        self.notificationManager = notificationManager
        logger.debug("NotificationManager set")
    }
    
    // MARK: - SwitchControlling Conformance
    
    /// Start the controller and perform initial evaluation.
    /// 
    /// This method starts the controller and performs an initial evaluation of the current conditions to determine if an audio device switch is needed.
    /// 
    /// - Throws: `SwitchControllerError` if an error occurs during startup.
    public func start() throws {
        logger.info("Starting SwitchController")
        
        try startMonitoringInternal()
        _ = try evaluateAndSwitchInternal()
    }
    
    /// Evaluate current conditions and switch audio devices if necessary.
    /// 
    /// This method evaluates the current conditions and switches audio devices if necessary.
    /// 
    /// - Returns: `true` if an audio device switch occurred, `false` otherwise.
    /// - Throws: `SwitchControllerError` if an error occurs during evaluation and switching.
    public func evaluateAndSwitch() throws -> Bool {
        do {
            return try evaluateAndSwitchInternal()
        } catch {
            logger.error("Error during evaluation and switching: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Start monitoring all relevant state changes.
    /// 
    /// This method starts monitoring all relevant state changes, including lid state, display connections, and audio devices.
    /// 
    /// - Throws: `SwitchControllerError` if an error occurs during monitoring.
    public func startMonitoring() throws {
        try startMonitoringInternal()
    }
    
    /// Stop monitoring all state changes.
    /// 
    /// This method stops monitoring all state changes.
    public func stopMonitoring() {
        lidMonitor.stopMonitoring()
        displayMonitor.stopMonitoring()
        audioDeviceMonitor.stopMonitoring()
    }
    
    /// Internal implementation that can throw errors.
    private func startMonitoringInternal() throws {
        logger.info("Starting all monitors")
        // Set up lid state change handler
        lidMonitor.onLidStateChange = { [weak self] isOpen in
            guard let self = self else { return }
            self.handleLidStateChange(isOpen: isOpen)
        }
        // Set up display connection change handler
        displayMonitor.onDisplayConnectionChange = { [weak self] isConnected in
            guard let self = self else { return }
            self.handleDisplayConnectionChange(isConnected: isConnected)
        }
        // Start individual monitors
        do {
            try lidMonitor.startMonitoring()
            logger.debug("Lid state monitor started successfully")
        } catch {
            logger.error("Failed to start lid state monitor: \(error.localizedDescription)")
            notificationManager?.sendNotification(
                title: "Error",
                body: "Failed to start lid state monitor: \(error.localizedDescription)"
            )
            throw SwitchControllerError.monitoringFailure(error.localizedDescription)
        }
        do {
            try displayMonitor.startMonitoring()
            logger.debug("Display monitor started successfully")
        } catch {
            logger.error("Failed to start display monitor: \(error.localizedDescription)")
            notificationManager?.sendNotification(
                title: "Error",
                body: "Failed to start display monitor: \(error.localizedDescription)"
            )
            throw SwitchControllerError.monitoringFailure(error.localizedDescription)
        }
        do {
            try audioDeviceMonitor.startMonitoring()
            logger.debug("Audio device monitor started successfully")
        } catch {
            logger.error("Failed to start audio device monitor: \(error.localizedDescription)")
            notificationManager?.sendNotification(
                title: "Error",
                body: "Failed to start audio device monitor: \(error.localizedDescription)"
            )
            throw SwitchControllerError.monitoringFailure(error.localizedDescription)
        }
    }
    
    /// Internal implementation that can throw errors.
    private func evaluateAndSwitchInternal() throws -> Bool {
        let lidClosed = !lidMonitor.isLidOpen
        let externalDisplayConnected = displayMonitor.isExternalDisplayConnected
        
        logger.debug("Evaluating conditions: Lid \(lidClosed ? "closed" : "open"), External display \(externalDisplayConnected ? "connected" : "disconnected")")
        
        // Check if we should switch to target microphone
        if lidClosed && externalDisplayConnected {
            logger.info("Conditions met for switching to target microphone")
            return try switchToTargetMicrophone()
        }
        
        // Check if we should revert to fallback microphone
        if !lidClosed && preferences.revertToFallbackOnLidOpen && fallbackMicrophoneUID != nil {
            logger.info("Conditions met for reverting to fallback microphone")
            return try revertToFallbackMicrophone()
        }
        
        logger.debug("No audio device switching needed")
        return false
    }
    
    /// Switch to the target microphone.
    /// 
    /// This method switches to the target microphone based on the current conditions.
    /// 
    /// - Returns: `true` if the switch was successful, `false` otherwise.
    /// - Throws: `SwitchControllerError` if an error occurs during switching.
    private func switchToTargetMicrophone() throws -> Bool {
        // Get the target microphone UID from preferences
        guard let targetUID = preferences.targetMicrophoneUID else {
            logger.warning("No target microphone configured in preferences")
            return false
        }
        
        // Get the current default device to store as fallback
        switch audioSwitcher.getDefaultInputDeviceID() {
        case .success(let deviceID):
            fallbackMicrophoneID = deviceID
            let availableDevices = audioDeviceMonitor.availableInputDevices
            fallbackMicrophoneUID = availableDevices.first(where: { $0.id == deviceID })?.uid
            logger.debug("Stored fallback microphone ID: \(deviceID)")
        case .failure(let error):
            logger.error("Could not get current default device: \(error.localizedDescription)")
            notificationManager?.sendNotification(
                title: "Device Query Failed",
                body: "Could not determine current audio device"
            )
            throw SwitchControllerError.audioSwitchingFailure(error.localizedDescription)
        }
        
        // Find the target device in available devices
        let availableDevices = audioDeviceMonitor.availableInputDevices
        guard let targetDevice = availableDevices.first(where: { $0.uid == targetUID }) else {
            logger.warning("Target microphone with UID \(targetUID) not found in available devices")
            return false
        }
        
        // Check if the target device is already the default
        switch audioSwitcher.getDefaultInputDeviceID() {
        case .success(let currentDeviceID):
            if currentDeviceID == targetDevice.id {
                logger.info("Target microphone is already the default device")
                return false
            }
        case .failure(let error):
            logger.error("Could not get current default device: \(error.localizedDescription)")
        }
        
        // Switch to target device
        logger.info("Switching to target microphone: \(targetDevice.name)")
        switch audioSwitcher.setDefaultInputDevice(uid: targetUID) {
        case .success:
            logger.info("Successfully switched to target microphone: \(targetDevice.name)")
            notificationManager?.sendNotification(
                title: "Microphone Switched",
                body: "Now using \(targetDevice.name)"
            )
            return true
        case .failure(let error):
            logger.error("Failed to switch to target microphone: \(error.localizedDescription)")
            notificationManager?.sendNotification(
                title: "Switch Failed",
                body: "Could not switch to \(targetDevice.name)"
            )
            throw SwitchControllerError.audioSwitchingFailure(error.localizedDescription)
        }
    }
    
    /// Revert to the fallback microphone.
    /// 
    /// This method reverts to the fallback microphone based on the current conditions.
    /// 
    /// - Returns: `true` if the revert was successful, `false` otherwise.
    /// - Throws: `SwitchControllerError` if an error occurs during reverting.
    private func revertToFallbackMicrophone() throws -> Bool {
        // Check if we have a fallback device stored
        guard let fallbackUID = fallbackMicrophoneUID else {
            logger.warning("No fallback microphone available")
            return false
        }
        
        // Find the fallback device in available devices
        let availableDevices = audioDeviceMonitor.availableInputDevices
        guard let fallbackDevice = availableDevices.first(where: { $0.uid == fallbackUID }) else {
            logger.warning("Fallback microphone not found in available devices")
            return false
        }
        
        // Check if the fallback device is already the default
        switch audioSwitcher.getDefaultInputDeviceID() {
        case .success(let currentDeviceID):
            if currentDeviceID == fallbackDevice.id {
                logger.info("Fallback microphone is already the default device")
                return false
            }
        case .failure(let error):
            logger.error("Could not get current default device: \(error.localizedDescription)")
        }
        
        // Switch to fallback device
        logger.info("Reverting to fallback microphone: \(fallbackDevice.name)")
        switch audioSwitcher.setDefaultInputDevice(uid: fallbackUID) {
        case .success:
            logger.info("Successfully reverted to fallback microphone: \(fallbackDevice.name)")
            notificationManager?.sendNotification(
                title: "Microphone Reverted",
                body: "Now using \(fallbackDevice.name)"
            )
            return true
        case .failure(let error):
            logger.error("Failed to revert to fallback microphone: \(error.localizedDescription)")
            notificationManager?.sendNotification(
                title: "Revert Failed",
                body: "Could not revert to \(fallbackDevice.name)"
            )
            throw SwitchControllerError.audioSwitchingFailure(error.localizedDescription)
        }
    }
    
    // MARK: - Event Handlers
    
    /// Handles lid state changes.
    /// 
    /// This method is called when the lid state changes, and it evaluates if an audio device switch is needed.
    private func handleLidStateChange(isOpen: Bool) {
        logger.info("Lid state changed: \(isOpen ? "Open" : "Closed")")
        logger.info("External display: \(self.displayMonitor.isExternalDisplayConnected ? "Connected" : "Disconnected")")
        
        // Evaluate if we need to switch audio devices
        do {
            let switchOccurred = try evaluateAndSwitchInternal()
            logger.debug("Audio switch evaluation result: \(switchOccurred ? "switched" : "no change needed")")
        } catch {
            logger.error("Error evaluating and switching audio devices: \(error.localizedDescription)")
        }
    }
    
    /// Handles display connection changes.
    /// 
    /// This method is called when the display connection changes, and it evaluates if an audio device switch is needed.
    private func handleDisplayConnectionChange(isConnected: Bool) {
        logger.info("Display connection changed: \(isConnected ? "Connected" : "Disconnected")")
        logger.info("Lid state: \(self.lidMonitor.isLidOpen ? "Open" : "Closed")")
        
        // Evaluate if we need to switch audio devices
        do {
            let switchOccurred = try evaluateAndSwitchInternal()
            logger.debug("Audio switch evaluation result: \(switchOccurred ? "switched" : "no change needed")")
        } catch {
            logger.error("Error evaluating and switching audio devices: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Public Diagnostic Methods
    
    /// Force a switch to the target microphone regardless of conditions.
    /// 
    /// This method forces a switch to the target microphone, regardless of the current conditions.
    /// 
    /// - Returns: `true` if the switch was successful, `false` otherwise.
    /// - Throws: `SwitchControllerError` if an error occurs during switching.
    @discardableResult
    public func forceAudioDeviceSwitch() throws -> Bool {
        logger.info("Force switch requested")
        
        // Get the target microphone UID from preferences
        guard let targetUID = preferences.targetMicrophoneUID else {
            logger.error("No target microphone configured")
            notificationManager?.sendNotification(
                title: "Switch Failed",
                body: "No target microphone configured in preferences"
            )
            return false
        }
        
        // Find the target device in available devices
        let availableDevices = audioDeviceMonitor.availableInputDevices
        guard let targetDevice = availableDevices.first(where: { $0.uid == targetUID }) else {
            logger.error("Target microphone not found in available devices")
            notificationManager?.sendNotification(
                title: "Switch Failed",
                body: "Target microphone not found or disconnected"
            )
            return false
        }
        
        // Store current device as fallback
        switch audioSwitcher.getDefaultInputDeviceID() {
        case .success(let deviceID):
            fallbackMicrophoneID = deviceID
            fallbackMicrophoneUID = availableDevices.first(where: { $0.id == deviceID })?.uid
            logger.debug("Stored fallback microphone: \(deviceID)")
        case .failure(let error):
            logger.error("Could not get current device for fallback: \(error.localizedDescription)")
        }
        
        // Switch to target device
        switch audioSwitcher.setDefaultInputDevice(uid: targetUID) {
        case .success:
            logger.info("Successfully switched to target microphone: \(targetDevice.name)")
            notificationManager?.sendNotification(
                title: "Microphone Switched",
                body: "Now using \(targetDevice.name)"
            )
            return true
        case .failure(let error):
            logger.error("Failed to switch to target microphone: \(error.localizedDescription)")
            notificationManager?.sendNotification(
                title: "Force Switch Failed",
                body: "Could not switch to \(targetDevice.name)"
            )
            throw SwitchControllerError.audioSwitchingFailure(error.localizedDescription)
        }
    }
    
    /// Force a revert to the fallback microphone.
    /// 
    /// This method forces a revert to the fallback microphone, regardless of the current conditions.
    /// 
    /// - Returns: `true` if the revert was successful, `false` otherwise.
    /// - Throws: `SwitchControllerError` if an error occurs during reverting.
    @discardableResult
    public func forceRevertToFallback() throws -> Bool {
        logger.info("Force revert requested")
        
        // Check if we have a fallback device stored
        guard let fallbackUID = fallbackMicrophoneUID else {
            logger.error("No fallback microphone available")
            notificationManager?.sendNotification(
                title: "Revert Failed",
                body: "No fallback microphone available"
            )
            return false
        }
        
        // Find the fallback device in available devices
        let availableDevices = audioDeviceMonitor.availableInputDevices
        guard let fallbackDevice = availableDevices.first(where: { $0.uid == fallbackUID }) else {
            logger.error("Fallback microphone not found in available devices")
            notificationManager?.sendNotification(
                title: "Revert Failed",
                body: "Fallback microphone not found or disconnected"
            )
            return false
        }
        
        // Switch to fallback device
        switch audioSwitcher.setDefaultInputDevice(uid: fallbackUID) {
        case .success:
            logger.info("Successfully reverted to fallback microphone: \(fallbackDevice.name)")
            notificationManager?.sendNotification(
                title: "Microphone Reverted",
                body: "Now using \(fallbackDevice.name)"
            )
            return true
        case .failure(let error):
            logger.error("Failed to revert to fallback microphone: \(error.localizedDescription)")
            notificationManager?.sendNotification(
                title: "Revert Failed",
                body: "Could not revert to \(fallbackDevice.name)"
            )
            throw SwitchControllerError.audioSwitchingFailure(error.localizedDescription)
        }
    }
    
    /// Diagnose audio device switching issues.
    /// 
    /// This method logs comprehensive diagnostic information about the current state, including the lid state, display connection, target microphone, and available devices.
    public func diagnoseAudioSwitchingIssues() {
        // Log current state
        let lidOpen = lidMonitor.isLidOpen
        let externalDisplayConnected = displayMonitor.isExternalDisplayConnected
        let targetMicUID = preferences.targetMicrophoneUID
        
        logger.info("Running diagnostic analysis")
        logger.info("Current state: lid \(lidOpen ? "open" : "closed"), external display \(externalDisplayConnected ? "connected" : "disconnected"), target mic UID: \(targetMicUID ?? "not set")")
        
        // Notify the user that diagnostics are running
        notificationManager?.sendNotification(
            title: "Diagnostics Running",
            body: "Checking audio switching configuration"
        )
        
        // Log available devices
        let availableDevices = audioDeviceMonitor.availableInputDevices
        logger.info("Available input devices: \(availableDevices.count)")
        
        for device in availableDevices {
            logger.info("Device: \(device.name), ID: \(device.id), UID: \(device.uid)")
        }
        
        // Check if target device is available
        if let targetUID = targetMicUID {
            if availableDevices.contains(where: { $0.uid == targetUID }) {
                logger.info("Target microphone is available")
            } else {
                logger.warning("Target microphone is NOT available")
                notificationManager?.sendNotification(
                    title: "Diagnostic Warning",
                    body: "Target microphone is not available"
                )
            }
        } else {
            logger.warning("No target microphone configured")
            notificationManager?.sendNotification(
                title: "Diagnostic Warning",
                body: "No target microphone configured"
            )
        }
        
        // Check current default device
        switch audioSwitcher.getDefaultInputDeviceID() {
        case .success(let deviceID):
            if let device = availableDevices.first(where: { $0.id == deviceID }) {
                logger.info("Current default device: \(device.name)")
            } else {
                logger.warning("Current default device (ID: \(deviceID)) not found in available devices")
            }
        case .failure(let error):
            logger.error("Could not get current default device: \(error.localizedDescription)")
        }
        
        notificationManager?.sendNotification(
            title: "Diagnostics Complete",
            body: "Check logs for detailed information"
        )
    }
}