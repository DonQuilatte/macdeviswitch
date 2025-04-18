import Foundation
import CoreAudio
import os.log

// Protocol for the controller (optional, but good for testing)
public protocol SwitchControlling {
    func start()
    // Add methods to handle state changes from monitors
}

public final class SwitchController: SwitchControlling {
    private let logger = Logger(subsystem: "com.yourcompany.macdeviswitchkit", category: "SwitchController") // Replace

    private let lidMonitor: LidStateMonitoring
    private let displayMonitor: DisplayMonitoring
    private let audioDeviceMonitor: AudioDeviceMonitoring
    private let audioSwitcher: AudioSwitching
    private let preferences: PreferenceManaging

    // Store the UID of the mic that was active before switching to external
    private var fallbackMicrophoneUID: String? = nil
    private var fallbackMicrophoneID: AudioDeviceID? = nil // Store ID too for quicker revert

    // Inject dependencies
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
        logger.debug("Initializing SwitchController")
    }

    public func start() {
        logger.info("Starting SwitchController monitoring.")
        // TODO: Register as a listener/delegate for changes from monitors
        // For now, we'll assume monitors are initialized and have current state.
        // Initial check might be needed based on current state.
    }

    // Placeholder: Method to be called when lid state changes
    private func lidStateChanged(isOpen: Bool) {
        logger.info("Lid state changed event received: \(isOpen ? "Open" : "Closed")")
        evaluateAndSwitch()
    }

    // Placeholder: Method to be called when display connection changes
    private func displayConnectionChanged(isConnected: Bool) {
        logger.info("Display connection changed event received: \(isConnected ? "Connected" : "Disconnected")")
        evaluateAndSwitch()
    }

    // Placeholder: Method to be called when audio device list changes
    private func audioDevicesChanged() {
        logger.info("Audio device list changed event received.")
        // Re-check if the target device is still valid?
        // Could trigger evaluateAndSwitch if target device appeared/disappeared
        evaluateAndSwitch()
    }

    // The core logic based on PRD section 4.1
    internal func evaluateAndSwitch() {
        let isLidCurrentlyOpen = lidMonitor.isLidOpen
        let isExternalDisplayConnected = displayMonitor.isExternalDisplayConnected
        guard let targetMicUID = preferences.targetMicrophoneUID else {
            logger.debug("Evaluation skipped: No target microphone set.")
            return
        }

        // Find the target device among currently available ones
        guard let targetDevice = audioDeviceMonitor.availableInputDevices.first(where: { $0.uid == targetMicUID }) else {
            logger.warning("Evaluation skipped: Target microphone (UID: \(targetMicUID)) is not currently available.")
            // TODO: Maybe reset fallback mic if target disappears?
            return
        }

        guard let currentDefaultInputID = audioSwitcher.getDefaultInputDeviceID() else {
             logger.error("Evaluation failed: Could not get current default input device ID.")
             return
        }

        logger.debug("Evaluating state: LidOpen=\(isLidCurrentlyOpen), ExtDisplay=\(isExternalDisplayConnected), Target=\(targetMicUID), CurrentDefaultID=\(currentDefaultInputID)")

        // --- Logic for Lid Close (Entering Clamshell) --- PRD 4.1.2
        if !isLidCurrentlyOpen && isExternalDisplayConnected {
            logger.debug("Condition: Lid Closed + External Display Connected")
            if currentDefaultInputID != targetDevice.id {
                logger.info("Action: Current default (\(currentDefaultInputID)) is not target (\(targetDevice.id)). Attempting switch.")
                // Store fallback *before* switching
                // Get UID for current default
                if let currentDefaultInfo = audioDeviceMonitor.availableInputDevices.first(where: { $0.id == currentDefaultInputID }) {
                     self.fallbackMicrophoneUID = currentDefaultInfo.uid
                     self.fallbackMicrophoneID = currentDefaultInfo.id // Store ID for direct revert
                     logger.info("Stored fallback microphone: \(self.fallbackMicrophoneUID ?? "nil") (ID: \(self.fallbackMicrophoneID ?? 0))")
                } else {
                    logger.warning("Could not get info for current default device ID \(currentDefaultInputID) to store fallback.")
                    self.fallbackMicrophoneUID = nil // Clear fallback if we can't identify it
                    self.fallbackMicrophoneID = nil
                }

                // Perform the switch
                if audioSwitcher.setDefaultInputDevice(deviceID: targetDevice.id) {
                    logger.info("Successfully switched to target microphone: \(targetDevice.name)")
                    // Post Notification (handled by NotificationManager via delegate/publisher later)
                } else {
                    logger.error("Failed to switch to target microphone: \(targetDevice.name)")
                    // Post Error Notification
                    // Clear fallback since switch failed?
                    self.fallbackMicrophoneUID = nil
                    self.fallbackMicrophoneID = nil
                }
            } else {
                logger.debug("Condition satisfied, but current default is already the target. No action needed.")
            }
        }
        // --- Logic for Lid Open (Exiting Clamshell) --- PRD 4.1.3
        else if isLidCurrentlyOpen {
            // Only revert if we previously stored a fallback and the preference is set
            logger.debug("Condition: Lid Open")
            if currentDefaultInputID == targetDevice.id,
               let fallbackID = self.fallbackMicrophoneID,
               fallbackID != 0, // Ensure fallback ID is valid
               self.preferences.revertOnLidOpen
            {
                logger.info("Action: Current default is target, fallback exists (ID: \(fallbackID)), and preference is true. Attempting revert.")
                if audioSwitcher.setDefaultInputDevice(deviceID: fallbackID) {
                    logger.info("Successfully reverted to fallback microphone (ID: \(fallbackID)).")
                    // Clear fallback state after successful revert
                    self.fallbackMicrophoneUID = nil
                    self.fallbackMicrophoneID = nil
                    // Post Notification
                } else {
                    logger.error("Failed to revert to fallback microphone (ID: \(fallbackID)).")
                    // Post Error Notification
                    // Should we clear fallback state even if revert fails?
                }
            } else {
                 logger.debug("No revert action needed. Conditions not met (Current=\(currentDefaultInputID), Target=\(targetDevice.id), FallbackID=\(self.fallbackMicrophoneID ?? 0), RevertPref=\(self.preferences.revertOnLidOpen))")
            }
             // If lid opens but ext display disconnects simultaneously, the previous block handles it.
             // If lid opens and display stays connected, but we shouldn't revert, do nothing.
        }
         // --- Other conditions (e.g., lid closed, no external display) --- implicitly do nothing
         else {
             logger.debug("Condition: Lid Closed / No External Display. No automatic switching action.")
         }
    }
}

// TODO:
// 1. Implement actual delegate/publisher pattern for monitors to call these change handlers.
// 2. Add publisher/delegate from SwitchController to notify App layer (e.g., StatusBarController) about state changes (active mic, errors).
// 3. Refine error handling and state management (e.g., what happens if target mic disconnects?).
// 4. Ensure thread safety if monitors call back on different threads.
