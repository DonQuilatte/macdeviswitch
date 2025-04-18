import Foundation
import CoreAudio // Needed for AudioDeviceID
@testable import MacDeviSwitchKit

// MARK: - Mock LidStateMonitor

class MockLidStateMonitor: LidStateMonitoring {
    var isLidOpen: Bool = true // Default state, controllable by tests
    var onLidStateChange: ((Bool) -> Void)? = nil
    
    func startMonitoring() {
        // No-op for mock
    }
    
    func stopMonitoring() {
        // No-op for mock
    }
}

// MARK: - Mock DisplayMonitor

class MockDisplayMonitor: DisplayMonitoring {
    var isExternalDisplayConnected: Bool = false // Default state, controllable by tests
    var onDisplayConnectionChange: ((Bool) -> Void)? = nil
    
    func startMonitoring() {
        // No-op for mock
    }
    
    func stopMonitoring() {
        // No-op for mock
    }
}

// MARK: - Mock AudioDeviceMonitor

class MockAudioDeviceMonitor: AudioDeviceMonitoring {
    var availableInputDevices: [AudioDeviceInfo] = [] // Controllable by tests

    func startMonitoring() {
        // No-op for mock
    }
    
    func stopMonitoring() {
        // No-op for mock
    }
    
    // Helper to easily add devices
    func addDevice(id: AudioDeviceID, uid: String, name: String) {
        availableInputDevices.append(AudioDeviceInfo(id: id, uid: uid, name: name, isInput: true))
    }
}

// MARK: - Mock AudioSwitcher

class MockAudioSwitcher: AudioSwitching {
    var setDefaultInputDeviceUIDCalledWith: String? = nil
    var setDefaultInputDeviceIDCalledWith: AudioDeviceID? = nil
    var getDefaultInputDeviceIDReturnValue: AudioDeviceID? = kAudioObjectUnknown // Controllable
    var setDefaultInputDeviceShouldSucceed: Bool = true // Controllable

    // --- Protocol Methods ---
    func setDefaultInputDevice(uid: String) -> Bool {
        setDefaultInputDeviceUIDCalledWith = uid
        // Simulate finding the ID based on UID (or test can set it directly)
        if let device = (MockAudioDeviceMonitor().availableInputDevices.first { $0.uid == uid }) {
             return setDefaultInputDevice(deviceID: device.id)
        } else {
            print("Mock Error: Could not find device ID for UID \(uid) in mock data")
            return false // Simulate not finding the device
        }
    }

    func setDefaultInputDevice(deviceID: AudioDeviceID) -> Bool {
        setDefaultInputDeviceIDCalledWith = deviceID
        // Update the 'current' default if successful, for subsequent getDefault calls
        if setDefaultInputDeviceShouldSucceed {
            getDefaultInputDeviceIDReturnValue = deviceID
        }
        return setDefaultInputDeviceShouldSucceed
    }

    func getDefaultInputDeviceID() -> AudioDeviceID? {
        return getDefaultInputDeviceIDReturnValue
    }

    // --- Test Helpers ---
    func resetMockState() {
        setDefaultInputDeviceUIDCalledWith = nil
        setDefaultInputDeviceIDCalledWith = nil
        // Don't reset getDefaultInputDeviceIDReturnValue here, let tests control it
        setDefaultInputDeviceShouldSucceed = true
    }
}

// MARK: - Mock PreferenceManager

class MockPreferenceManager: PreferenceManaging {
    var targetMicrophoneUID: String? = nil
    var revertOnLidOpen: Bool = true
    var showNotifications: Bool = true
}

// MARK: - Mock NotificationManager

class MockNotificationManager: NotificationManaging {
    var lastTitle: String? = nil
    var lastBody: String? = nil
    var notificationCount: Int = 0
    
    func sendNotification(title: String, body: String) {
        lastTitle = title
        lastBody = body
        notificationCount += 1
    }
    
    func resetMockState() {
        lastTitle = nil
        lastBody = nil
        notificationCount = 0
    }
}
