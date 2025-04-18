import Foundation
import CoreAudio
import os.log

// Structure to hold relevant device info
public struct AudioDeviceInfo: Identifiable, Hashable {
    public let id: AudioDeviceID // Raw CoreAudio ID
    public let uid: String
    public let name: String
    public let isInput: Bool
    // Add other properties if needed (e.g., manufacturer)
}

public protocol AudioDeviceMonitoring {
    var availableInputDevices: [AudioDeviceInfo] { get }
    // Add publisher/delegate for changes
}

public final class AudioDeviceMonitor: AudioDeviceMonitoring {
    fileprivate let logger = Logger(subsystem: "com.yourcompany.macdeviswitchkit", category: "AudioDeviceMonitor") // Replace
    public private(set) var availableInputDevices: [AudioDeviceInfo] = []

    private var propertyListenerBlock: AudioObjectPropertyListenerBlock?
    private var systemObjectAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    public init() {
        logger.debug("Initializing AudioDeviceMonitor")
        updateDeviceList()
        registerForDeviceChanges()
    }

    deinit {
        logger.debug("Deinitializing AudioDeviceMonitor")
        unregisterForDeviceChanges()
    }

    private func registerForDeviceChanges() {
        propertyListenerBlock = { [weak self] (inNumberOfAddresses, inAddresses) in
            self?.logger.debug("Received audio hardware property change notification.")
            // Check if kAudioHardwarePropertyDevices is one of the changed properties
            // (Could check inAddresses if needed for more granular updates)
            self?.updateDeviceList()
        }

        let err = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &systemObjectAddress, nil, propertyListenerBlock!)
        if err != noErr {
            logger.error("Error adding property listener block: \(err)")
        }
    }

    private func unregisterForDeviceChanges() {
        if let block = propertyListenerBlock {
            let err = AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &systemObjectAddress, nil, block)
            if err != noErr {
                logger.error("Error removing property listener block: \(err)")
            }
            propertyListenerBlock = nil // Release the block
        }
    }

    fileprivate func updateDeviceList() {
        logger.debug("Updating audio device list...")
        var size: UInt32 = 0
        var propertyAddress = systemObjectAddress

        // Get the size of the device list
        var err = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &size)
        guard err == noErr else {
            logger.error("Error getting size for device list: \(err)")
            return
        }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.stride
        if deviceCount == 0 {
            logger.info("No audio devices found.")
            setDeviceList([])
            return
        }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &size, &deviceIDs)
        guard err == noErr else {
            logger.error("Error getting device list: \(err)")
            return
        }

        var currentDevices: [AudioDeviceInfo] = []
        for deviceID in deviceIDs {
            if let deviceInfo = getDeviceInfo(deviceID: deviceID), deviceInfo.isInput {
                 currentDevices.append(deviceInfo)
            }
        }

        setDeviceList(currentDevices)
    }

    private func setDeviceList(_ newDevices: [AudioDeviceInfo]) {
        let sortedNewDevices = newDevices.sorted { $0.name < $1.name }
        if availableInputDevices != sortedNewDevices {
            logger.info("Audio input device list changed. Count: \(sortedNewDevices.count)")
            availableInputDevices = sortedNewDevices
            // Notify delegate/publisher here later
            logger.debug("Available input devices: \(self.availableInputDevices.map { $0.name })")
        }
    }

    // Helper to get info for a single device
    private func getDeviceInfo(deviceID: AudioDeviceID) -> AudioDeviceInfo? {
        guard let uid = getDeviceStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID) else {
            logger.warning("Failed to get UID for device ID \(deviceID)")
            return nil
        }
        guard let name = getDeviceStringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName) else {
             logger.warning("Failed to get Name for device ID \(deviceID) (UID: \(uid))")
             return nil // Name is crucial
        }

        let isInput = hasInputStreams(deviceID: deviceID)

        return AudioDeviceInfo(id: deviceID, uid: uid, name: name, isInput: isInput)
    }

    // Helper to check for input streams
    private func hasInputStreams(deviceID: AudioDeviceID) -> Bool {
        var size: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput, // Check Input scope
            mElement: kAudioObjectPropertyElementMain
        )

        let err = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &size)
        if err == noErr && size > 0 {
            return true
        } else {
            // Fallback check if Input scope fails (some virtual devices might use Output scope for input streams?)
            // propertyAddress.mScope = kAudioObjectPropertyScopeOutput
            // let errOutput = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &size)
            // return errOutput == noErr && size > 0
            return false
        }
    }

    /// Retrieves a string property from an audio device using CoreAudio APIs
    /// - Parameters:
    ///   - deviceID: The audio device ID to query
    ///   - selector: The property selector to retrieve
    /// - Returns: The string value of the property, or nil if retrieval fails
    private func getDeviceStringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var size: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
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
            logger.error("Error getting property \(selector) for device \(deviceID): \(err)")
            return nil
        }
    }
}
