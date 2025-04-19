import Foundation
import CoreAudio
import os.log

// MARK: - Shared Types

/// Error types for audio device switching operations
public enum AudioSwitcherError: Error, LocalizedError {
    case deviceNotFound(uid: String)
    case deviceIDNotFound
    case switchFailed(deviceID: AudioDeviceID, status: OSStatus)
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

/// Information about an audio device
public struct AudioDeviceInfo: Identifiable, Hashable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let isInput: Bool
    public let isOutput: Bool

    public init(id: AudioDeviceID, uid: String, name: String, isInput: Bool, isOutput: Bool = false) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isInput = isInput
        self.isOutput = isOutput
    }
}
