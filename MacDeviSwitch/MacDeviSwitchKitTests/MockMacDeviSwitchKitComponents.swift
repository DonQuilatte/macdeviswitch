import Foundation
import CoreAudio
import XCTest

@testable import MacDeviSwitchKit

// Define MockError for stubbing
enum MockError: Error, LocalizedError {
    case notStubbed
    case simulatedError

    var errorDescription: String? {
        switch self {
        case .notStubbed: return "Mock function was called but not stubbed."
        case .simulatedError: return "A simulated error occurred."
        }
    }
}

// MARK: - Mock LidStateMonitor

class MockLidStateMonitor: LidStateMonitoring {
    var isLidOpen: Bool = true // Default state, controllable by tests
    var onLidStateChange: ((Bool) -> Void)?

    func startMonitoring() throws {
        // No-op for mock
    }

    func stopMonitoring() {
        // No-op for mock
    }
}

// MARK: - Mock DisplayMonitor

class MockDisplayMonitor: DisplayMonitoring {
    var isExternalDisplayConnected: Bool = false // Default state, controllable by tests
    var onDisplayConnectionChange: ((Bool) -> Void)?

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
    private var _currentDefaultDeviceID: AudioDeviceID?
    var setDefaultInputDeviceIDCalledWith: AudioDeviceID?
    var setDefaultInputDeviceUIDCalledWith: String?
    var setDefaultInputDeviceError: Error?
    var getDeviceUIDCalledWith: AudioDeviceID?
    // Store the stubbed result, tests should set this appropriately. Use uid: String for deviceNotFound.
    var getDeviceUIDResultStub: Result<String, AudioSwitcherError> = .failure(.deviceNotFound(uid: "mock_default_uid_not_found"))

    // Helper to set initial state
    func setCurrentDefaultDeviceID(_ id: AudioDeviceID?) {
        self._currentDefaultDeviceID = id
    }

    // Match protocol signature
    func getDefaultInputDeviceID() -> Result<AudioDeviceID, AudioSwitcherError> {
        if let id = _currentDefaultDeviceID {
            return .success(id)
        } else {
            // Use the correct error case: .deviceIDNotFound
            return .failure(.deviceIDNotFound)
        }
    }

    func setDefaultInputDevice(deviceID: AudioDeviceID) -> Result<Void, AudioSwitcherError> {
        setDefaultInputDeviceIDCalledWith = deviceID
        if let error = setDefaultInputDeviceError {
            // Use the correct error case: .switchFailed
            // Using a placeholder status code. Could also try to map the generic error if needed.
            let status: OSStatus = -1 // Placeholder status
            return .failure(.switchFailed(deviceID: deviceID, status: status))
        } else {
            self._currentDefaultDeviceID = deviceID
            return .success(())
        }
    }

    func setDefaultInputDevice(uid: String) -> Result<Void, AudioSwitcherError> {
        setDefaultInputDeviceUIDCalledWith = uid
        // Simulate success or failure based on the general error property
        // Note: This doesn't simulate looking up the ID from UID, just success/failure of setting.
        if let error = setDefaultInputDeviceError {
            // Use the correct error case: .switchFailed (needs an ID, which we don't have directly here)
            // Or perhaps deviceNotFound is more appropriate if the error simulation implies the UID lookup failed.
            // Let's use deviceNotFound for now, assuming the error relates to finding the device by UID.
            return .failure(.deviceNotFound(uid: uid))
        } else {
            // We don't know the ID corresponding to the UID in the mock, so we can't update
            // _currentDefaultDeviceID directly here. Tests needing this flow might need more complex stubbing.
            // For now, just simulate success.
            return .success(())
        }
    }

    // Match protocol signature
    func getDeviceUID(for deviceID: AudioDeviceID) -> Result<String, AudioSwitcherError> {
        getDeviceUIDCalledWith = deviceID
        // Return the stubbed result set by the test
        return getDeviceUIDResultStub
    }

    // Reinstate resetMockState used by tests
    func resetMockState() {
        setDefaultInputDeviceIDCalledWith = nil
        setDefaultInputDeviceUIDCalledWith = nil
        setDefaultInputDeviceError = nil
        getDeviceUIDCalledWith = nil
        // Reset stub to a default failure state
        getDeviceUIDResultStub = .failure(.deviceNotFound(uid: "mock_default_uid_not_found"))
        // Don't reset _currentDefaultDeviceID here, let tests control initial state via setCurrentDefaultDeviceID
    }
}

// MARK: - Mock PreferenceManager

class MockPreferenceManager: PreferenceManaging {
    var targetMicrophoneUID: String?
    var revertToFallbackOnLidOpen: Bool = true // Renamed to match protocol
    var showNotifications: Bool = true
}

// MARK: - Mock NotificationManager

class MockNotificationManager: NotificationManaging {
    var lastTitle: String?
    var lastBody: String?
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

// MARK: - Mock DeviceSelector

struct DetermineTargetUIDParams {
    let lidIsOpen: Bool
    let isExternalDisplayConnected: Bool
    let preferences: PreferenceManaging
    let currentDefaultDeviceID: AudioDeviceID?
    let fallbackDeviceID: AudioDeviceID?
}

class MockDeviceSelector: DeviceSelecting {
    var determineTargetDeviceUIDCalled = false
    var stubbedTargetUID: String?
    var determineTargetDeviceUIDParams: DetermineTargetUIDParams?

    func determineTargetDeviceUID(
        lidIsOpen: Bool,
        isExternalDisplayConnected: Bool,
        preferences: PreferenceManaging,
        currentDefaultDeviceID: AudioDeviceID?,
        fallbackDeviceID: AudioDeviceID?
    ) -> String? {
        determineTargetDeviceUIDCalled = true
        determineTargetDeviceUIDParams = DetermineTargetUIDParams(
            lidIsOpen: lidIsOpen,
            isExternalDisplayConnected: isExternalDisplayConnected,
            preferences: preferences,
            currentDefaultDeviceID: currentDefaultDeviceID,
            fallbackDeviceID: fallbackDeviceID
        )
        return stubbedTargetUID
    }
}
