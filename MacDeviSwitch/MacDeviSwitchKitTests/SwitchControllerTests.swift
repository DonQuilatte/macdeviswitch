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

    // Controller Under Test
    var switchController: SwitchController!

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

        // Initialize Controller with Mocks
        switchController = SwitchController(
            lidMonitor: mockLidMonitor,
            displayMonitor: mockDisplayMonitor,
            audioDeviceMonitor: mockAudioDeviceMonitor,
            audioSwitcher: mockAudioSwitcher,
            preferences: mockPreferences
        )

        // Setup common initial state (can be overridden in tests)
        // Add both mics to the monitor
        mockAudioDeviceMonitor.addDevice(id: internalMicID, uid: internalMicUID, name: internalMicName)
        mockAudioDeviceMonitor.addDevice(id: externalMicID, uid: externalMicUID, name: externalMicName)
        // Set initial default device in the switcher
        mockAudioSwitcher.getDefaultInputDeviceIDReturnValue = internalMicID
        // Set target device in preferences
        mockPreferences.targetMicrophoneUID = externalMicUID
    }

    override func tearDownWithError() throws {
        mockLidMonitor = nil
        mockDisplayMonitor = nil
        mockAudioDeviceMonitor = nil
        mockAudioSwitcher = nil
        mockPreferences = nil
        switchController = nil
        try super.tearDownWithError()
    }

    // MARK: - Test Cases: Lid Close (Entering Clamshell) - PRD 4.1.2

    func testEvaluateAndSwitch_WhenLidCloses_WithExtDisplay_AndTargetSet_AndNotCurrent_ShouldSwitchToTarget() {
        // Arrange
        mockLidMonitor.isLidOpen = false
        mockDisplayMonitor.isExternalDisplayConnected = true
        mockAudioSwitcher.getDefaultInputDeviceIDReturnValue = internalMicID // Start on internal
        mockPreferences.targetMicrophoneUID = externalMicUID

        // Act
        switchController.evaluateAndSwitch() // Access internal method for testing

        // Assert
        XCTAssertEqual(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith, externalMicID, "Should attempt to set default device to the external mic ID.")
        // TODO: Check fallback state storage in SwitchController if made accessible for testing or via side effects
    }

    func testEvaluateAndSwitch_WhenLidCloses_WithExtDisplay_AndTargetIsCurrent_ShouldNotSwitch() {
        // Arrange
        mockLidMonitor.isLidOpen = false
        mockDisplayMonitor.isExternalDisplayConnected = true
        mockAudioSwitcher.getDefaultInputDeviceIDReturnValue = externalMicID // Start on external (target)
        mockPreferences.targetMicrophoneUID = externalMicUID
        mockAudioSwitcher.resetMockState() // Reset call trackers

        // Act
        switchController.evaluateAndSwitch()

        // Assert
        XCTAssertNil(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith, "Should NOT attempt to set default device if already the target.")
    }

    func testEvaluateAndSwitch_WhenLidCloses_NoExtDisplay_ShouldNotSwitch() {
        // Arrange
        mockLidMonitor.isLidOpen = false
        mockDisplayMonitor.isExternalDisplayConnected = false // No external display
        mockAudioSwitcher.getDefaultInputDeviceIDReturnValue = internalMicID
        mockPreferences.targetMicrophoneUID = externalMicUID
        mockAudioSwitcher.resetMockState()

        // Act
        switchController.evaluateAndSwitch()

        // Assert
        XCTAssertNil(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith, "Should NOT switch if external display is not connected.")
    }

    func testEvaluateAndSwitch_WhenLidCloses_WithExtDisplay_NoTargetSet_ShouldNotSwitch() {
        // Arrange
        mockLidMonitor.isLidOpen = false
        mockDisplayMonitor.isExternalDisplayConnected = true
        mockAudioSwitcher.getDefaultInputDeviceIDReturnValue = internalMicID
        mockPreferences.targetMicrophoneUID = nil // No target set
        mockAudioSwitcher.resetMockState()

        // Act
        switchController.evaluateAndSwitch()

        // Assert
        XCTAssertNil(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith, "Should NOT switch if no target microphone is set.")
    }

     func testEvaluateAndSwitch_WhenLidCloses_WithExtDisplay_TargetNotAvailable_ShouldNotSwitch() {
        // Arrange
        mockLidMonitor.isLidOpen = false
        mockDisplayMonitor.isExternalDisplayConnected = true
        mockAudioSwitcher.getDefaultInputDeviceIDReturnValue = internalMicID
        mockPreferences.targetMicrophoneUID = "NonExistentMic_UID" // Target not in available list
        mockAudioSwitcher.resetMockState()

        // Act
        switchController.evaluateAndSwitch()

        // Assert
        XCTAssertNil(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith, "Should NOT switch if target microphone is not available.")
    }

    // MARK: - Test Cases: Lid Open (Exiting Clamshell) - PRD 4.1.3

    func testEvaluateAndSwitch_WhenLidOpens_CurrentIsTarget_RevertPrefTrue_ShouldRevertToFallback() {
        // Arrange
        // 1. Simulate a previous switch: Lid closed, ext display, switched to external
        mockLidMonitor.isLidOpen = false
        mockDisplayMonitor.isExternalDisplayConnected = true
        mockAudioSwitcher.getDefaultInputDeviceIDReturnValue = internalMicID
        mockPreferences.targetMicrophoneUID = externalMicUID
        switchController.evaluateAndSwitch() // This sets the fallback internally
        XCTAssertEqual(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith, externalMicID) // Verify switch happened
        mockAudioSwitcher.resetMockState() // Reset tracker for next step

        // 2. Now, open the lid
        mockLidMonitor.isLidOpen = true
        mockPreferences.revertOnLidOpen = true // Ensure revert is enabled
        // Current device is now externalMicID as set by the mock switcher
        XCTAssertEqual(mockAudioSwitcher.getDefaultInputDeviceID(), externalMicID)

        // Act
        switchController.evaluateAndSwitch()

        // Assert
        XCTAssertEqual(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith, internalMicID, "Should attempt to revert to the original internal mic ID.")
        // TODO: Check fallback state cleared if accessible
    }

    func testEvaluateAndSwitch_WhenLidOpens_CurrentIsTarget_RevertPrefFalse_ShouldNotRevert() {
        // Arrange
        // 1. Simulate previous switch
        mockLidMonitor.isLidOpen = false
        mockDisplayMonitor.isExternalDisplayConnected = true
        mockAudioSwitcher.getDefaultInputDeviceIDReturnValue = internalMicID
        mockPreferences.targetMicrophoneUID = externalMicUID
        switchController.evaluateAndSwitch() // Sets fallback
        XCTAssertEqual(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith, externalMicID)
        mockAudioSwitcher.resetMockState()

        // 2. Open lid, but disable revert
        mockLidMonitor.isLidOpen = true
        mockPreferences.revertOnLidOpen = false // Revert DISABLED
        XCTAssertEqual(mockAudioSwitcher.getDefaultInputDeviceID(), externalMicID)

        // Act
        switchController.evaluateAndSwitch()

        // Assert
        XCTAssertNil(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith, "Should NOT revert if revertOnLidOpen preference is false.")
    }

    func testEvaluateAndSwitch_WhenLidOpens_CurrentNotTarget_ShouldNotRevert() {
         // Arrange
        // 1. Simulate previous switch
        mockLidMonitor.isLidOpen = false
        mockDisplayMonitor.isExternalDisplayConnected = true
        mockAudioSwitcher.getDefaultInputDeviceIDReturnValue = internalMicID
        mockPreferences.targetMicrophoneUID = externalMicUID
        switchController.evaluateAndSwitch() // Sets fallback
        XCTAssertEqual(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith, externalMicID)
        mockAudioSwitcher.resetMockState()

        // 2. Open lid, enable revert, BUT simulate user manually changed mic *after* lid closed
        mockLidMonitor.isLidOpen = true
        mockPreferences.revertOnLidOpen = true
        mockAudioSwitcher.getDefaultInputDeviceIDReturnValue = internalMicID // Manually set back to internal

        // Act
        switchController.evaluateAndSwitch()

        // Assert
        XCTAssertNil(mockAudioSwitcher.setDefaultInputDeviceIDCalledWith, "Should NOT revert if current device is not the target device.")
    }

    // TODO: Add tests for scenarios where switch fails (mockAudioSwitcher.setDefaultInputDeviceShouldSucceed = false)
    // TODO: Add tests for scenarios where getting current default device fails (mockAudioSwitcher.getDefaultInputDeviceIDReturnValue = nil)
}
