import Foundation
import CoreAudio
import os.log

/// Default implementation for selecting the target audio device.
public struct DefaultDeviceSelector: DeviceSelecting {
    private let logger = Logger(subsystem: "via.MacDeviSwitch.kit", category: "DefaultDeviceSelector")

    public init() {}

    /// Determines the target audio device UID based on system state and preferences.
    /// This implementation prioritizes the target device when the lid is closed or an external display is connected.
    /// It reverts to the fallback device when the lid is open and no external display is connected, if configured.
    public func determineTargetDeviceUID(
        lidIsOpen: Bool,
        isExternalDisplayConnected: Bool,
        preferences: PreferenceManaging,
        currentDefaultDeviceID: AudioDeviceID?,
        fallbackDeviceID: AudioDeviceID?
    ) -> String? {
        logger.debug("Evaluating state: Lid Open = \(lidIsOpen), External Display = \(isExternalDisplayConnected)")
        let targetUID = preferences.targetMicrophoneUID
        let shouldRevert = preferences.revertToFallbackOnLidOpen

        // Condition to switch to the target device: Lid closed OR external display connected
        let shouldSwitchToTarget = !lidIsOpen || isExternalDisplayConnected

        if shouldSwitchToTarget {
            guard let targetUID = targetUID, !targetUID.isEmpty else {
                logger.debug("Condition met for target device, but no target UID configured.")
                return nil // No target configured
            }
            // Avoid switching if already on the target device (check UID if possible, fallback to ID if needed)
            // Note: We don't have the current device UID easily here, only ID. A full comparison might need more info.
            // If currentDefaultDeviceID matches fallbackDeviceID, it suggests we previously switched to target.
            // If current is *not* fallback, we might already be on target.
            // Simplification: Switch if targetUID is set and condition is met. SwitchController handles actual switching logic.
            logger.info("Condition met for target device: UID \(targetUID)")
            return targetUID
        } else {
            // Condition to revert to fallback: Lid is open AND no external display AND revert enabled
            if lidIsOpen && !isExternalDisplayConnected && shouldRevert {
                // Check if we actually have a fallback device ID stored from a previous switch
                guard let fallbackID = fallbackDeviceID else {
                    logger.debug("Condition met for fallback, but no fallback ID available (was never switched from?).")
                    return nil
                }
                // Check if we are currently on the target device (or what *was* the target device when fallbackID was set)
                // This logic is complex. Let's assume if we are *not* on fallbackID, we should try to revert.
                // The check in SwitchController prevents unnecessary switches if already on fallback.
                if currentDefaultDeviceID != fallbackID {
                    logger.info("Condition met to revert to fallback device (ID: \(fallbackID)). Returning nil to signal revert intent.")
                    // Returning nil signals SwitchController to attempt revert using its stored fallback UID.
                    // We don't know the fallback UID here directly.
                    return nil // Signal revert needed
                } else {
                    logger.debug("Condition met for fallback, but already on the fallback device.")
                    return nil // Already on fallback
                }
            } else {
                logger.debug("Conditions not met for target or fallback switch.")
                return nil // No switch needed based on current logic
            }
        }
    }
}
