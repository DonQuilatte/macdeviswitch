import Foundation
import CoreAudio
import os.log

/// Errors that can occur during audio device switching operations
public enum AudioSwitcherError: Error, LocalizedError {
    /// The audio device with the specified UID was not found.
    case deviceNotFound(uid: String)
    /// The default audio device ID could not be retrieved.
    case deviceIDNotFound
    /// Switching to the specified device failed.
    case switchFailed(deviceID: AudioDeviceID, status: OSStatus)
    /// Accessing an audio property failed.
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

/// A protocol for switching the system's default audio input device.
public protocol AudioSwitching {
    /// Sets the default system input device based on its UID.
    /// - Parameter uid: The unique identifier string of the target device.
    /// - Returns: A result indicating success or a specific error.
    func setDefaultInputDevice(uid: String) -> Result<Void, AudioSwitcherError>
    
    /// Sets the default system input device based on its CoreAudio ID.
    /// - Parameter deviceID: The CoreAudio ID of the target device.
    /// - Returns: A result indicating success or a specific error.
    func setDefaultInputDevice(deviceID: AudioDeviceID) -> Result<Void, AudioSwitcherError>
    
    /// Gets the current default system input device ID.
    /// - Returns: The `AudioDeviceID` of the current default input, or an error if retrieval fails.
    func getDefaultInputDeviceID() -> Result<AudioDeviceID, AudioSwitcherError>
}

/// Handles changing the system's default audio input device.
public final class AudioSwitcher: AudioSwitching {
    private let logger = Logger(subsystem: "via.MacDeviSwitch.kit", category: "AudioSwitcher")

    /// Initializes a new instance of the `AudioSwitcher` class.
    public init() {
        logger.debug("Initializing AudioSwitcher")
    }

    /// Sets the default system input device based on its UID.
    /// - Parameter uid: The unique identifier string of the target device.
    /// - Returns: A result indicating success or a specific error.
    public func setDefaultInputDevice(uid: String) -> Result<Void, AudioSwitcherError> {
        logger.debug("Attempting to set default input device by UID: \(uid)")
        guard let deviceID = findDeviceID(byUID: uid) else {
            logger.error("Could not find device ID for UID: \(uid)")
            return .failure(.deviceNotFound(uid: uid))
        }
        return setDefaultInputDevice(deviceID: deviceID)
    }

    /// Sets the default system input device based on its CoreAudio ID.
    /// - Parameter deviceID: The CoreAudio ID of the target device.
    /// - Returns: A result indicating success or a specific error.
    public func setDefaultInputDevice(deviceID: AudioDeviceID) -> Result<Void, AudioSwitcherError> {
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
            return .success(())
        } else {
            logger.error("Failed to set default input device to ID \(deviceID). Error: \(err)")
            return .failure(.switchFailed(deviceID: deviceID, status: err))
        }
    }

    /// Gets the current default system input device ID.
    /// - Returns: The `AudioDeviceID` of the current default input, or an error if retrieval fails.
    public func getDefaultInputDeviceID() -> Result<AudioDeviceID, AudioSwitcherError> {
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
            return .success(deviceID)
        } else {
            logger.error("Failed to get default input device ID. Error: \(err)")
            return .failure(.propertyAccessFailed(selector: kAudioHardwarePropertyDefaultInputDevice, status: err))
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
        guard err == noErr else { 
            logger.error("Failed to get device list size. Error: \(err)")
            return nil 
        }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.stride
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &size, &deviceIDs)
        guard err == noErr else { 
            logger.error("Failed to get device list. Error: \(err)")
            return nil 
        }

        for deviceID in deviceIDs {
            if getDeviceUID(deviceID: deviceID) == uid {
                return deviceID
            }
        }
        
        logger.warning("Device with UID \(uid) not found in available devices")
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
        guard err == noErr, size > 0 else {
            logger.warning("Failed to get UID property size for device \(deviceID). Error: \(err)")
            return nil 
        }

        var cfString: CFString?
        err = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &cfString)

        if err == noErr, let stringValue = cfString as String? {
            return stringValue
        } else {
            logger.warning("Failed to get UID for device \(deviceID). Error: \(err)")
            return nil
        }
    }
}
