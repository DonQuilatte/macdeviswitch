import Foundation
import CoreAudio
import os.log

/// Main controller coordinating device switching logic.
public class SwitchController: SwitchControlling {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.jederlichman.MacDeviSwitch", category: "SwitchController")

    private let lidMonitor: LidStateMonitoring
    private let displayMonitor: DisplayMonitoring
    private let audioDeviceMonitor: AudioDeviceMonitoring
    private let audioSwitcher: AudioSwitching
    private let preferences: PreferenceManaging
    private let deviceSelector: DeviceSelecting
    private let eventHandler: EventHandling
    private var notificationManager: NotificationManaging?

    // Store the current and fallback device IDs
    private var currentDefaultDeviceID: AudioDeviceID?
    private var fallbackDeviceID: AudioDeviceID? // Store the ID that was default before we switched

    /// Initializes the controller with necessary dependencies.
    public init(
        lidMonitor: LidStateMonitoring,
        displayMonitor: DisplayMonitoring,
        audioDeviceMonitor: AudioDeviceMonitoring,
        audioSwitcher: AudioSwitching,
        preferences: PreferenceManaging,
        deviceSelector: DeviceSelecting, // Add DeviceSelecting
        eventHandler: EventHandling // Add EventHandling
    ) {
        self.lidMonitor = lidMonitor
        self.displayMonitor = displayMonitor
        self.audioDeviceMonitor = audioDeviceMonitor
        self.audioSwitcher = audioSwitcher
        self.preferences = preferences
        self.deviceSelector = deviceSelector
        self.eventHandler = eventHandler
    }

    public func setNotificationManager(_ notificationManager: NotificationManaging) {
        self.notificationManager = notificationManager
    }

    public func start() throws {
        SwitchController.logger.info("Starting SwitchController.")
        do {
            // Get initial default device ID
            updateCurrentDefaultDeviceID()

            try startMonitoring()
            // Perform initial check
            _ = try evaluateAndSwitch()
            SwitchController.logger.info("SwitchController started successfully.")
        } catch {
            SwitchController.logger.error("Failed to start SwitchController: \(error.localizedDescription)")
            // Propagate the error
            throw error
        }
    }

    public func startMonitoring() throws {
        SwitchController.logger.info("Starting monitoring for lid, display, and audio devices.")
        // Use the eventHandler to manage starting the monitors
        eventHandler.startHandlingEvents(
            lidMonitor: lidMonitor,
            displayMonitor: displayMonitor,
            onEvent: { [weak self] in
                self?.handleSystemEvent()
            }
        )
        // Audio device monitoring needs to be started separately if not handled by eventHandler
        // Assuming audioDeviceMonitor has its own mechanism or needs direct start here.
        // If AudioDeviceMonitor changes trigger evaluation, integrate that logic.
        // For now, let's assume it updates its 'availableInputDevices' list which
        // evaluateAndSwitch uses.
        audioDeviceMonitor.startMonitoring() // Ensure this is called
    }

    public func stopMonitoring() {
        SwitchController.logger.info("Stopping monitoring.")
        // Use the eventHandler to manage stopping the monitors
        eventHandler.stopHandlingEvents(lidMonitor: lidMonitor, displayMonitor: displayMonitor)
        audioDeviceMonitor.stopMonitoring() // Ensure this is called
    }

    /// Called when a relevant system event (lid, display) occurs.
    private func handleSystemEvent() {
        SwitchController.logger.debug("System event received, evaluating and switching...")
        do {
            _ = try evaluateAndSwitch()
        } catch {
            SwitchController.logger.error("Error during event-triggered evaluation: \(error.localizedDescription)")
        }
    }

    /// Fetches and updates the `currentDefaultDeviceID` property.
    private func updateCurrentDefaultDeviceID() {
        switch audioSwitcher.getDefaultInputDeviceID() {
        case .success(let id):
            self.currentDefaultDeviceID = id
            SwitchController.logger.debug("Updated current default device ID: \(id)")
        case .failure(let error):
            SwitchController.logger.error("Failed to get current default device ID: \(error.localizedDescription)")
            self.currentDefaultDeviceID = nil // Reset if failed
        }
    }

    public func evaluateAndSwitch() throws -> Bool {
        SwitchController.logger.info("Evaluating conditions for audio device switch...")

        // Ensure we have the latest default device ID before making decisions
        updateCurrentDefaultDeviceID()

        let lidIsOpen = lidMonitor.isLidOpen
        let isExternalDisplayConnected = displayMonitor.isExternalDisplayConnected
        SwitchController.logger.debug("Current state: Lid Open=\(lidIsOpen), External Display=\(isExternalDisplayConnected)")

        // Use the DeviceSelecting protocol to determine the target UID
        guard let targetDeviceUID = deviceSelector.determineTargetDeviceUID(
            lidIsOpen: lidIsOpen,
            isExternalDisplayConnected: isExternalDisplayConnected,
            preferences: preferences,
            currentDefaultDeviceID: self.currentDefaultDeviceID, // Pass current ID
            fallbackDeviceID: self.fallbackDeviceID // Pass fallback ID
        ) else {
            SwitchController.logger.info("Device selector determined no switch needed.")
            return false // No target UID means no switch needed
        }

        SwitchController.logger.info("Target device UID determined: \(targetDeviceUID)")

        // Find the AudioDeviceID for the target UID
        guard let targetDeviceID = findDeviceID(forUID: targetDeviceUID) else {
            SwitchController.logger.error("Could not find device ID for target UID: \(targetDeviceUID)")
            throw SwitchControllerError.deviceNotFound(uid: targetDeviceUID)
        }

        // Check if a switch is actually required (target is not already the default)
        if let currentID = self.currentDefaultDeviceID, currentID == targetDeviceID {
            SwitchController.logger.info("Target device (ID: \(targetDeviceID)) is already the default. No switch needed.")
            return false
        }

        SwitchController.logger.info("Switching default input device to ID: \(targetDeviceID) (UID: \(targetDeviceUID))")

        // Store the current default ID as the fallback *before* switching
        // Only store if it's not the target we are switching to (prevents fallback loop)
        if let currentID = self.currentDefaultDeviceID, currentID != targetDeviceID {
            self.fallbackDeviceID = currentID
            SwitchController.logger.debug("Stored fallback device ID: \(currentID)")
        } else if self.currentDefaultDeviceID == nil {
             self.fallbackDeviceID = nil // Clear fallback if current was unknown
             SwitchController.logger.debug("Current default device ID was unknown, clearing fallback.")
        }

        // Perform the switch
        let switchResult = audioSwitcher.setDefaultInputDevice(deviceID: targetDeviceID)

        switch switchResult {
        case .success:
            let deviceName = getDeviceName(for: targetDeviceID) ?? "Unknown Device"
            SwitchController.logger.info("Successfully switched default input device to \(deviceName) (ID: \(targetDeviceID))")
            self.currentDefaultDeviceID = targetDeviceID // Update our tracked current ID

            // Send notification if enabled
            if preferences.showNotifications {
                notificationManager?.sendNotification(
                    title: "Audio Input Switched",
                    body: "Default input set to \(deviceName)"
                )
            }
            return true // Switch occurred

        case .failure(let error):
            SwitchController.logger.error("Failed to switch audio device: \(error.localizedDescription)")
            // Reset fallback ID if switch failed?
            // self.fallbackDeviceID = nil // Or keep it to potentially retry/revert?
            throw SwitchControllerError.switchFailed(underlyingError: error)
        }
    }

    // Helper to find device ID from UID using the monitor's list
    private func findDeviceID(forUID uid: String) -> AudioDeviceID? {
        return audioDeviceMonitor.availableInputDevices.first { $0.uid == uid }?.id
    }

    // Helper to get device name from ID using the monitor's list
    private func getDeviceName(for id: AudioDeviceID) -> String? {
        return audioDeviceMonitor.availableInputDevices.first { $0.id == id }?.name
    }
}

/// Errors specific to the SwitchController.
enum SwitchControllerError: LocalizedError {
    case monitoringStartFailed(String)
    case switchFailed(underlyingError: Error)
    case deviceNotFound(uid: String)

    public var errorDescription: String? {
        switch self {
        case .monitoringStartFailed(let reason):
            return "Failed to start monitoring: \(reason)"
        case .switchFailed(let underlyingError):
            return "Failed to switch audio device: \(underlyingError.localizedDescription)"
        case .deviceNotFound(let uid):
            return "Required audio device not found (UID: \(uid))"
        }
    }
}
