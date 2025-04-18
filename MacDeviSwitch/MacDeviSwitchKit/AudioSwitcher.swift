import Foundation
import CoreAudio
import os.log

public protocol AudioSwitching {
    func setDefaultInputDevice(uid: String) -> Bool
    func setDefaultInputDevice(deviceID: AudioDeviceID) -> Bool
    func getDefaultInputDeviceID() -> AudioDeviceID?
}

public final class AudioSwitcher: AudioSwitching {
    private let logger = Logger(subsystem: "com.yourcompany.macdeviswitchkit", category: "AudioSwitcher") // Replace

    public init() {
        logger.debug("Initializing AudioSwitcher")
    }

    /// Sets the default system input device based on its UID.
    /// - Parameter uid: The unique identifier string of the target device.
    /// - Returns: `true` if successful, `false` otherwise.
    public func setDefaultInputDevice(uid: String) -> Bool {
        logger.debug("Attempting to set default input device by UID: \(uid)")
        guard let deviceID = findDeviceID(byUID: uid) else {
            logger.error("Could not find device ID for UID: \(uid)")
            return false
        }
        return setDefaultInputDevice(deviceID: deviceID)
    }

    /// Sets the default system input device based on its CoreAudio ID.
    /// - Parameter deviceID: The CoreAudio ID of the target device.
    /// - Returns: `true` if successful, `false` otherwise.
    public func setDefaultInputDevice(deviceID: AudioDeviceID) -> Bool {
        logger.info("Setting default input device to ID: \(deviceID)")
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceIDVar = deviceID // Need a mutable variable to pass its address
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let err = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, dataSize, &deviceIDVar)

        if err == noErr {
            logger.info("Successfully set default input device to ID: \(deviceID)")
            return true
        } else {
            logger.error("Failed to set default input device to ID \(deviceID). Error: \(err)")
            // Log specific error details if possible (e.g., permissions, device not valid input)
            return false
        }
    }

    /// Gets the current default system input device ID.
    /// - Returns: The `AudioDeviceID` of the current default input, or `nil` if an error occurs.
    public func getDefaultInputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceID)

        if err == noErr {
            logger.debug("Current default input device ID: \(deviceID)")
            return deviceID
        } else {
            logger.error("Failed to get default input device ID. Error: \(err)")
            return nil
        }
    }

    // Helper to find device ID by UID (could be moved to AudioDeviceMonitor or a shared utility)
    private func findDeviceID(byUID uid: String) -> AudioDeviceID? {
        var size: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var err = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &size)
        guard err == noErr else { return nil }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.stride
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &size, &deviceIDs)
        guard err == noErr else { return nil }

        for deviceID in deviceIDs {
            if getDeviceUID(deviceID: deviceID) == uid {
                return deviceID
            }
        }
        return nil // Not found
    }

    /// Retrieves the UID for a given audio device ID
    /// - Parameter deviceID: The audio device ID to query
    /// - Returns: The device UID as a String, or nil if retrieval fails
    private func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        var size: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var err = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &size)
        guard err == noErr, size > 0 else { return nil }

        var cfString: CFString?
        err = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &cfString)

        if err == noErr, let stringValue = cfString as String? {
            return stringValue
        } else {
            return nil
        }
    }
}
