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

    /// Logic for selecting the target device.
    private let deviceSelector: DeviceSelecting

    /// Handles system events (lid, display).
    private let eventHandler: EventHandling

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
    ///   - deviceSelector: Logic for selecting the target device.
    ///   - eventHandler: Handles system events (lid, display).
    public init(
        lidMonitor: LidStateMonitoring,
        displayMonitor: DisplayMonitoring,
        audioDeviceMonitor: AudioDeviceMonitoring,
        audioSwitcher: AudioSwitching,
        preferences: PreferenceManaging,
        deviceSelector: DeviceSelecting,
        eventHandler: EventHandling
    ) {
        self.lidMonitor = lidMonitor
        self.displayMonitor = displayMonitor
        self.audioDeviceMonitor = audioDeviceMonitor
        self.audioSwitcher = audioSwitcher
        self.preferences = preferences
        self.deviceSelector = deviceSelector
        self.eventHandler = eventHandler

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
        eventHandler.stopHandlingEvents(lidMonitor: lidMonitor, displayMonitor: displayMonitor)
        lidMonitor.stopMonitoring()
        displayMonitor.stopMonitoring()
        audioDeviceMonitor.stopMonitoring()
        logger.info("All monitors stopped")
    }

    /// Internal implementation that can throw errors.
    private func startMonitoringInternal() throws {
        logger.info("Starting all monitors")

        // Use the event handler to set up callbacks
        eventHandler.startHandlingEvents(
            lidMonitor: lidMonitor,
            displayMonitor: displayMonitor,
            onEvent: { [weak self] in
                guard let self = self else { return }
                do {
                    _ = try self.evaluateAndSwitchInternal()
                } catch {
                    self.logger.error("Error triggered by event handler during evaluation: \(error.localizedDescription)")
                    // Optionally notify the user about the error triggered by the event
                    if self.preferences.showNotifications {
                        self.notificationManager?.sendNotification(title: "Evaluation Error", body: "Failed to evaluate state after event: \(error.localizedDescription)")
                    }
                }
            }
        )

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
        // Use the injected device selector
        let targetDeviceUID = deviceSelector.determineTargetDeviceUID(
            lidIsOpen: lidMonitor.isLidOpen,
            isExternalDisplayConnected: displayMonitor.isExternalDisplayConnected,
            preferences: preferences
        )

        // Get the current default input device UID to compare
        let currentDeviceID: AudioDeviceID
        switch audioSwitcher.getDefaultInputDeviceID() {
        case .success(let id):
            currentDeviceID = id
        case .failure(let error):
            logger.error("Failed to get current default input device ID: \(error.localizedDescription)")
            // Decide if we should attempt a switch even if we don't know the current device
            // For now, let's proceed cautiously and not switch if we can't verify the current state.
            // Alternatively, we could attempt to switch regardless, depending on desired behavior.
            return false
        }

        let currentDeviceUID = audioSwitcher.getDeviceUID(for: currentDeviceID)

        logger.info("Evaluating state: Lid Open=\(!lidMonitor.isLidOpen), External Display=\(displayMonitor.isExternalDisplayConnected)")
        logger.info("Preferences: LidOpen=\(preferences.lidOpenDeviceUID ?? "nil"), LidClosed=\(preferences.lidClosedDeviceUID ?? "nil"), External=\(preferences.externalMonitorDeviceUID ?? "nil")")
        logger.info("Determined target device UID: \(targetDeviceUID ?? "nil")")
        logger.info("Current default device UID: \(currentDeviceUID ?? "nil") (ID: \(currentDeviceID))")

        // If a target device is determined and it's different from the current one
        if let targetUID = targetDeviceUID, targetUID != currentDeviceUID {
            logger.info("Switch needed: Target UID '\(targetUID)' differs from current UID '\(currentDeviceUID ?? "nil")'")

            switch audioSwitcher.setDefaultInputDevice(uid: targetUID) {
            case .success:
                logger.info("Successfully switched input device to UID: \(targetUID)")
                notifySwitchSuccess(to: targetUID)
                return true // Switch occurred
            case .failure(let error):
                logger.error("Failed to switch input device to UID \(targetUID): \(error.localizedDescription)")
                notifySwitchFailure(for: targetUID, error: error)
                // Throw an error that can be caught by the public-facing method
                throw SwitchControllerError.audioSwitchingFailure(error.localizedDescription)
            }
        } else if targetDeviceUID == nil {
            logger.info("No specific device configured for the current state. No switch performed.")
        } else {
            logger.info("No switch needed: Target UID '\(targetDeviceUID!)' matches current UID '\(currentDeviceUID ?? "nil")'.")
        }

        return false // No switch occurred
    }

    /// Sends a notification if enabled in preferences about a successful switch.
    private func notifySwitchSuccess(to deviceUID: String) {
        guard preferences.showNotifications else { return }
        let deviceName = audioDeviceMonitor.getDeviceName(forUID: deviceUID) ?? "Unknown Device"
        notificationManager?.sendNotification(
            title: "Audio Input Switched",
            body: "Switched input to \(deviceName)"
        )
    }

    /// Sends a notification if enabled in preferences about a failed switch attempt.
    private func notifySwitchFailure(for deviceUID: String, error: Error) {
        guard preferences.showNotifications else { return }
        let deviceName = audioDeviceMonitor.getDeviceName(forUID: deviceUID) ?? "Target Device"
        notificationManager?.sendNotification(
            title: "Audio Switch Failed",
            body: "Could not switch input to \(deviceName). Error: \(error.localizedDescription)"
        )
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
