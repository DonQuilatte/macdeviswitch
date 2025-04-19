import Foundation
import CoreAudio
import os.log

/// Errors that can occur during audio device monitoring
public enum AudioDeviceMonitorError: Error, LocalizedError {
    case listenerRegistrationFailed(OSStatus)
    case listenerRemovalFailed(OSStatus)
    case deviceListQueryFailed(OSStatus)
    case devicePropertyQueryFailed(AudioDeviceID, AudioObjectPropertySelector, OSStatus)

    public var errorDescription: String? {
        switch self {
        case .listenerRegistrationFailed(let status):
            return "Failed to register audio device listener (Error: \(status))"
        case .listenerRemovalFailed(let status):
            return "Failed to remove audio device listener (Error: \(status))"
        case .deviceListQueryFailed(let status):
            return "Failed to query audio device list (Error: \(status))"
        case .devicePropertyQueryFailed(let deviceID, let selector, let status):
            return "Failed to query property \(selector) for device \(deviceID) (Error: \(status))"
        }
    }
}

/// Monitors audio device connections/disconnections using CoreAudio.
public final class AudioDeviceMonitor: AudioDeviceMonitoring {
    fileprivate let logger = Logger(subsystem: "via.MacDeviSwitch.kit", category: "AudioDeviceMonitor")

    /// The list of currently available audio input devices.
    public private(set) var availableInputDevices: [AudioDeviceInfo] = []

    private var propertyListenerBlock: AudioObjectPropertyListenerBlock?
    private var systemObjectAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    // Monitoring state
    private var isMonitoring: Bool = false

    /// Initializes a new instance of the `AudioDeviceMonitor` class.
    public init() {
        logger.debug("Initializing AudioDeviceMonitor")
        updateDeviceList()
    }

    deinit {
        logger.debug("Deinitializing AudioDeviceMonitor")
        stopMonitoring()
    }

    /// Starts monitoring audio device connections/disconnections.
    public func startMonitoring() {
        guard !isMonitoring else { return }
        logger.debug("Starting audio device monitoring")
        do {
            try registerForDeviceChanges()
            isMonitoring = true
        } catch {
            logger.error("Failed to start monitoring: \(error.localizedDescription)")
        }
    }

    /// Stops monitoring audio device connections/disconnections.
    public func stopMonitoring() {
        guard isMonitoring else { return }
        logger.debug("Stopping audio device monitoring")
        do {
            try unregisterForDeviceChanges()
            isMonitoring = false
        } catch {
            logger.error("Failed to stop monitoring: \(error.localizedDescription)")
        }
    }

    private func registerForDeviceChanges() throws {
        propertyListenerBlock = { [weak self] (_, _) in
            self?.logger.debug("Received audio hardware property change notification.")
            // Check if kAudioHardwarePropertyDevices is one of the changed properties
            // (Could check inAddresses if needed for more granular updates)
            self?.updateDeviceList()
        }

        let err = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &systemObjectAddress, nil, propertyListenerBlock!)
        if err != noErr {
            let baseMsg = "Error adding property listener block:"
            let statusString = "\(err)"
            logger.error("\(baseMsg) \(statusString)")
            throw AudioDeviceMonitorError.listenerRegistrationFailed(err)
        }
    }

    private func unregisterForDeviceChanges() throws {
        if let block = propertyListenerBlock {
            let err = AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &systemObjectAddress, nil, block)
            if err != noErr {
                let baseMsg = "Error removing property listener block:"
                let statusString = "\(err)"
                logger.error("\(baseMsg) \(statusString)")
                throw AudioDeviceMonitorError.listenerRemovalFailed(err)
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
            let baseMsg = "Error getting size for device list:"
            let statusString = "\(err)"
            logger.error("\(baseMsg) \(statusString)")
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
            let baseMsg = "Error getting device list:"
            let statusString = "\(err)"
            logger.error("\(baseMsg) \(statusString)")
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
            // Notify observers that the list has changed
            NotificationCenter.default.post(name: .AudioDevicesChangedNotification, object: nil)
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
        guard err == noErr, size > 0 else {
            let baseMsg = "Error getting property size for selector \(selector) on device \(deviceID):"
            let statusString = "\(err)"
            logger.warning("\(baseMsg) \(statusString)")
            return nil
        }

        var cfStringUnmanaged: Unmanaged<CFString>?
        err = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &cfStringUnmanaged)

        if err == noErr, let stringValue = cfStringUnmanaged?.takeRetainedValue() as String? {
            return stringValue
        } else {
            let baseMsg = "Error getting property \(selector) for device \(deviceID):"
            let statusString = "\(err)"
            logger.error("\(baseMsg) \(statusString)")
            return nil
        }
    }
}
