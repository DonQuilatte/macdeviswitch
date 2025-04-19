import Foundation
import CoreAudio
import os.log

/// Default implementation for selecting the target audio device.
public struct DefaultDeviceSelector: DeviceSelecting {
    private let logger = Logger(subsystem: "via.MacDeviSwitch.kit", category: "DefaultDeviceSelector")

    public init() {}

    /// Determines the target audio device UID based on system state and preferences.
    /// This implementation prioritizes the target device when the lid is closed and an external display is connected.
    public func determineTargetDeviceUID(
        lidIsOpen: Bool,
        isExternalDisplayConnected: Bool,
        preferences: PreferenceManaging,
        currentDefaultDeviceID: AudioDeviceID?,
        fallbackDeviceID: AudioDeviceID?
    ) -> String? {
        logger.debug("Evaluating state: Lid Open = \(lidIsOpen), External Display = \(isExternalDisplayConnected)")
        let targetUID = preferences.targetMicrophoneUID

        // Only switch to target in clamshell mode with an external display
        let shouldSwitchToTarget = (!lidIsOpen && isExternalDisplayConnected)
        guard shouldSwitchToTarget else {
            logger.debug("Not in clamshell-with-external-display; no target switch.")
            return nil
        }
        guard let targetUID = targetUID, !targetUID.isEmpty else {
            logger.debug("Clamshell + external display but no target UID configured.")
            return nil
        }
        logger.info("Switching to target mic UID: \(targetUID)")
        return targetUID
    }
}
