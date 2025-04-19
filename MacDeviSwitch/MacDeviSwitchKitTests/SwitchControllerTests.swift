import XCTest
import CoreAudio
@testable import MacDeviSwitchKit

class SwitchControllerTests: XCTestCase {

    // Mocks
    var mockLidMonitor: MockLidStateMonitor!
    var mockDisplayMonitor: MockDisplayMonitor!
    var mockAudioDeviceMonitor: MockAudioDeviceMonitor!
    var mockAudioSwitcher: MockAudioSwitcher!
    var mockPreferences: MockPreferenceManager!
    var mockNotificationManager: MockNotificationManager!
    var mockDeviceSelector: MockDeviceSelector!
    var switchController: SwitchController!
    var eventHandler: EventHandling!

    // Test Constants
    let internalMicID: AudioDeviceID = 1
    let internalMicUID = "BuiltInMicrophoneDevice_UID"
    let internalMicName = "MacBook Pro Microphone"

    let externalMicID: AudioDeviceID = 5
    let externalMicUID = "ExternalUSBMic_UID_XYZ"
    let externalMicName = "My USB Mic"

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Initialize Mocks
        mockLidMonitor = MockLidStateMonitor()
        mockDisplayMonitor = MockDisplayMonitor()
        mockAudioDeviceMonitor = MockAudioDeviceMonitor()
        mockAudioSwitcher = MockAudioSwitcher()
        mockPreferences = MockPreferenceManager()
        mockNotificationManager = MockNotificationManager()
        mockDeviceSelector = MockDeviceSelector()
        eventHandler = SwitchControllerEventHandler()

        // Initialize Controller with Mocks
        switchController = SwitchController(
            lidMonitor: mockLidMonitor,
            displayMonitor: mockDisplayMonitor,
            audioDeviceMonitor: mockAudioDeviceMonitor,
            audioSwitcher: mockAudioSwitcher,
            preferences: mockPreferences,
            deviceSelector: mockDeviceSelector,
            eventHandler: eventHandler
        )

        switchController.setNotificationManager(mockNotificationManager)

        // Setup common initial state (can be overridden in tests)
        // Add both mics to the monitor
        mockAudioDeviceMonitor.addDevice(id: internalMicID, uid: internalMicUID, name: internalMicName)
        mockAudioDeviceMonitor.addDevice(id: externalMicID, uid: externalMicUID, name: externalMicName)
        // Set initial default device in the switcher using the new helper
        mockAudioSwitcher.setCurrentDefaultDeviceID(internalMicID)
        // Set target device in preferences
        mockPreferences.targetMicrophoneUID = externalMicUID
    }

    override func tearDownWithError() throws {
        mockLidMonitor = nil
        mockDisplayMonitor = nil
        mockAudioDeviceMonitor = nil
        mockAudioSwitcher = nil
        mockPreferences = nil
        mockNotificationManager = nil
        mockDeviceSelector = nil
        eventHandler = nil
        switchController = nil
        try super.tearDownWithError()
    }

    // MARK: - Test Cases: Lid Close (Entering Clamshell) - PRD 4.1.2

    func testEvaluateAndSwitch_WhenLidCloses_WithExtDisplay_AndTargetSet_AndNotCurrent_ShouldSwitchToTarget() {
        // Arrange
        mockLidMonitor.isLidOpen = false
        mockDisplayMonitor.isExternalDisplayConnected = true
        mockAudioSwitcher.setCurrentDefaultDeviceID(internalMicID) // Start on internal
        mockPreferences.targetMicrophoneUID = externalMicUID
        mockDeviceSelector.stubbedTargetUID = externalMicUID // Selector should return target

        // Act
        XCTAssertNoThrow(try switchController.evaluateAndSwitch()) // Access internal method for testing

        // Assert
        XCTAssertEqual(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith, externalMicID,
                       "Should attempt to set default device to the external mic ID.")
        // Check fallback state storage in SwitchController if made accessible for testing or via side effects
    }

    func testEvaluateAndSwitch_WhenLidCloses_WithExtDisplay_AndTargetIsCurrent_ShouldNotSwitch() {
        // Arrange
        mockLidMonitor.isLidOpen = false
        mockDisplayMonitor.isExternalDisplayConnected = true
        // Start on external (target) - use helper
        mockAudioSwitcher.setCurrentDefaultDeviceID(externalMicID)
        mockPreferences.targetMicrophoneUID = externalMicUID
        // Selector *would* return target, but controller should see current == target
        mockDeviceSelector.stubbedTargetUID = externalMicUID
        mockAudioSwitcher.resetMockState() // Reset call trackers

        // Act
        XCTAssertNoThrow(try switchController.evaluateAndSwitch())

        // Assert
        XCTAssertNil(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith,
                     "Should NOT attempt to set default device if already the target.")
    }

    func testEvaluateAndSwitch_WhenLidCloses_NoExtDisplay_ShouldNotSwitch() {
        // Arrange
        mockLidMonitor.isLidOpen = false
        mockDisplayMonitor.isExternalDisplayConnected = false // No external display
        // Start on internal
        mockAudioSwitcher.setCurrentDefaultDeviceID(internalMicID)
        mockPreferences.targetMicrophoneUID = externalMicUID
        // Selector should determine no switch needed due to display state
        mockDeviceSelector.stubbedTargetUID = nil
        mockAudioSwitcher.resetMockState()

        // Act
        XCTAssertNoThrow(try switchController.evaluateAndSwitch())

        // Assert
        XCTAssertNil(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith,
                     "Should NOT switch if external display is not connected.")
    }

    func testEvaluateAndSwitch_WhenLidCloses_WithExtDisplay_NoTargetSet_ShouldNotSwitch() {
        // Arrange
        mockLidMonitor.isLidOpen = false
        mockDisplayMonitor.isExternalDisplayConnected = true
        // Start on internal
        mockAudioSwitcher.setCurrentDefaultDeviceID(internalMicID)
        mockPreferences.targetMicrophoneUID = nil // No target set
        // Selector should determine no switch needed due to missing preference
        mockDeviceSelector.stubbedTargetUID = nil
        mockAudioSwitcher.resetMockState()

        // Act
        XCTAssertNoThrow(try switchController.evaluateAndSwitch())

        // Assert
        XCTAssertNil(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith,
                     "Should NOT switch if no target microphone is set.")
    }

    func testEvaluateAndSwitch_WhenLidCloses_WithExtDisplay_TargetNotAvailable_ShouldNotSwitch() {
        // Arrange
        mockLidMonitor.isLidOpen = false
        mockDisplayMonitor.isExternalDisplayConnected = true
        // Start on internal
        mockAudioSwitcher.setCurrentDefaultDeviceID(internalMicID)
        mockPreferences.targetMicrophoneUID = "NonExistentMic_UID" // Target not in available list
        // Controller should find the UID from selector, but fail to find the ID
        mockDeviceSelector.stubbedTargetUID = "NonExistentMic_UID"
        mockAudioSwitcher.resetMockState()

        // Act
        // Expect error because the UID from selector won't map to an ID in AudioDeviceMonitor
        XCTAssertThrowsError(try switchController.evaluateAndSwitch()) { error in
            guard case SwitchControllerError.deviceNotFound(let uid) = error else {
                return XCTFail("Expected deviceNotFound error")
            }
            XCTAssertEqual(uid, "NonExistentMic_UID")
        }

        // Assert switch wasn't called (already checked by throw)
        XCTAssertNil(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith, "Switch should not have been attempted")
    }

    // MARK: - Test Cases: Lid Open (Exiting Clamshell) - PRD 4.1.3

    func testEvaluateAndSwitch_WhenLidOpens_CurrentIsTarget_RevertPrefTrue_ShouldRevertToFallback() {
        // 1. Simulate a previous switch: Lid closed, ext display, switched to external
        mockLidMonitor.isLidOpen = false
        mockDisplayMonitor.isExternalDisplayConnected = true
        mockAudioSwitcher.setCurrentDefaultDeviceID(internalMicID)
        mockPreferences.targetMicrophoneUID = externalMicUID
        mockDeviceSelector.stubbedTargetUID = externalMicUID // Selector triggers initial switch
        XCTAssertNoThrow(try switchController.evaluateAndSwitch()) // This sets the fallback internally
        XCTAssertEqual(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith, externalMicID) // Verify switch happened
        // Verify internal state of mock switcher was updated
        XCTAssertEqual(try? mockAudioSwitcher.getDefaultInputDeviceID().get(), externalMicID)
        mockAudioSwitcher.resetMockState() // Reset call trackers

        // 2. Now, open the lid
        mockLidMonitor.isLidOpen = true
        mockPreferences.revertToFallbackOnLidOpen = true // Ensure revert is enabled
        // Selector should now return the fallback UID to trigger revert
        mockDeviceSelector.stubbedTargetUID = internalMicUID

        // Act
        XCTAssertNoThrow(try switchController.evaluateAndSwitch())

        // Assert
        XCTAssertEqual(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith, internalMicID,
                       "Should attempt to revert to the original internal mic ID.")
        // Check fallback state cleared if accessible
    }

    func testEvaluateAndSwitch_WhenLidOpens_CurrentIsTarget_RevertPrefFalse_ShouldNotRevert() {
        // 1. Simulate previous switch
        mockLidMonitor.isLidOpen = false
        mockDisplayMonitor.isExternalDisplayConnected = true
        mockAudioSwitcher.setCurrentDefaultDeviceID(internalMicID)
        mockPreferences.targetMicrophoneUID = externalMicUID
        mockDeviceSelector.stubbedTargetUID = externalMicUID // Selector triggers initial switch
        XCTAssertNoThrow(try switchController.evaluateAndSwitch()) // Sets fallback
        XCTAssertEqual(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith, externalMicID)
        XCTAssertEqual(try? mockAudioSwitcher.getDefaultInputDeviceID().get(), externalMicID)
        mockAudioSwitcher.resetMockState()

        // 2. Open lid, but disable revert
        mockLidMonitor.isLidOpen = true
        mockPreferences.revertToFallbackOnLidOpen = false // Revert DISABLED
        // Selector should determine no switch needed
        mockDeviceSelector.stubbedTargetUID = nil

        // Act
        XCTAssertNoThrow(try switchController.evaluateAndSwitch())

        // Assert
        XCTAssertNil(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith,
                     "Should NOT revert if revertOnLidOpen preference is false.")
    }

    func testEvaluateAndSwitch_WhenLidOpens_CurrentNotTarget_ShouldNotRevert() {
        // 1. Simulate previous switch
        mockLidMonitor.isLidOpen = false
        mockDisplayMonitor.isExternalDisplayConnected = true
        mockAudioSwitcher.setCurrentDefaultDeviceID(internalMicID) // Start internal
        mockPreferences.targetMicrophoneUID = externalMicUID
        mockDeviceSelector.stubbedTargetUID = externalMicUID // Selector triggers initial switch
        XCTAssertNoThrow(try switchController.evaluateAndSwitch()) // Sets fallback, switches to external
        XCTAssertEqual(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith, externalMicID)
        XCTAssertEqual(try? mockAudioSwitcher.getDefaultInputDeviceID().get(), externalMicID)
        mockAudioSwitcher.resetMockState()

        // 2. Open lid, but assume current device is *not* the target anymore (manually changed?)
        mockLidMonitor.isLidOpen = true
        let someOtherDeviceID: AudioDeviceID = 999
        mockAudioSwitcher.setCurrentDefaultDeviceID(someOtherDeviceID)
        mockPreferences.revertToFallbackOnLidOpen = true // Revert enabled (but shouldn't trigger)
        // Selector should determine no switch needed as current device isn't the target
        mockDeviceSelector.stubbedTargetUID = nil

        // Act
        XCTAssertNoThrow(try switchController.evaluateAndSwitch())

        // Assert
        XCTAssertNil(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith,
                     "Should NOT revert if current device is not the target device.")
    }

    // Add tests for scenarios where switch fails (mockAudioSwitcher.setDefaultInputDeviceShouldSucceed = false)
    // Add tests for scenarios where getting current default device fails (mockAudioSwitcher.getDefaultInputDeviceIDResult = .failure())
}

// MARK: - Mock Dependencies

// (Existing mocks for LidStateMonitor, DisplayMonitor, etc.)

// Extend the existing MockMacDeviSwitchKitComponents.swift if that's where mocks live
