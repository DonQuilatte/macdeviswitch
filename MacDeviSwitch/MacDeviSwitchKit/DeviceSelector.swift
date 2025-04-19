import Foundation
import os.log

/// Protocol defining the requirements for selecting the target audio device.
protocol DeviceSelecting {
    /// Determines the target audio device UID based on the current system state and preferences.
    ///
    /// - Parameters:
    ///   - lidIsOpen: The current state of the laptop lid.
    ///   - isExternalDisplayConnected: Whether an external display is currently connected.
    ///   - preferences: The user's preference manager.
    /// - Returns: The UID of the target device, or nil if no specific device is configured for the state.
    func determineTargetDeviceUID(
        lidIsOpen: Bool,
        isExternalDisplayConnected: Bool,
        preferences: PreferenceManaging
    ) -> String?
}

/// Default implementation for selecting the target audio device.
struct DefaultDeviceSelector: DeviceSelecting {
    private let logger = Logger(subsystem: "via.MacDeviSwitch.kit", category: "DefaultDeviceSelector")

    func determineTargetDeviceUID(
        lidIsOpen: Bool,
        isExternalDisplayConnected: Bool,
        preferences: PreferenceManaging
    ) -> String? {
        let lidClosed = !lidIsOpen
        logger.debug("Determining target device: LidClosed=\(lidClosed), ExternalDisplay=\(isExternalDisplayConnected)")

        // Priority: External display overrides lid state if connected
        if isExternalDisplayConnected, let externalMonitorDeviceUID = preferences.externalMonitorDeviceUID {
            logger.debug("Prioritizing external display device: \(externalMonitorDeviceUID)")
            return externalMonitorDeviceUID
        }

        // If no external display, check lid state
        if lidClosed, let lidClosedDeviceUID = preferences.lidClosedDeviceUID {
            logger.debug("Using lid closed device: \(lidClosedDeviceUID)")
            return lidClosedDeviceUID
        } else if !lidClosed, let lidOpenDeviceUID = preferences.lidOpenDeviceUID {
            logger.debug("Using lid open device: \(lidOpenDeviceUID)")
            return lidOpenDeviceUID
        }

        // No specific device configured for the current state
        logger.debug("No specific device UID configured for current state.")
        return nil
    }
}
