import XCTest
@testable import MacDeviSwitchKit

final class DefaultDeviceSelectorTests: XCTestCase {
    var selector: DefaultDeviceSelector!
    var prefs: MockSelectorPrefs!

    override func setUp() {
        super.setUp()
        selector = DefaultDeviceSelector()
        prefs = MockSelectorPrefs()
    }

    override func tearDown() {
        selector = nil
        prefs = nil
        super.tearDown()
    }

    func test_noTargetConfigured_returnsNil() {
        prefs.targetMicrophoneUID = nil
        let result = selector.determineTargetDeviceUID(
            lidIsOpen: false,
            isExternalDisplayConnected: true,
            preferences: prefs,
            currentDefaultDeviceID: nil,
            fallbackDeviceID: nil
        )
        XCTAssertNil(result)
    }

    func test_emptyTargetConfigured_returnsNil() {
        prefs.targetMicrophoneUID = ""
        let result = selector.determineTargetDeviceUID(
            lidIsOpen: false,
            isExternalDisplayConnected: true,
            preferences: prefs,
            currentDefaultDeviceID: nil,
            fallbackDeviceID: nil
        )
        XCTAssertNil(result)
    }

    func test_clamshellWithDisplay_returnsTargetUID() {
        prefs.targetMicrophoneUID = "EXT-MIC-UID"
        let result = selector.determineTargetDeviceUID(
            lidIsOpen: false,
            isExternalDisplayConnected: true,
            preferences: prefs,
            currentDefaultDeviceID: nil,
            fallbackDeviceID: nil
        )
        XCTAssertEqual(result, "EXT-MIC-UID")
    }

    func test_lidClosedWithoutDisplay_returnsNil() {
        prefs.targetMicrophoneUID = "EXT"
        let result = selector.determineTargetDeviceUID(
            lidIsOpen: false,
            isExternalDisplayConnected: false,
            preferences: prefs,
            currentDefaultDeviceID: nil,
            fallbackDeviceID: nil
        )
        XCTAssertNil(result)
    }

    func test_displayConnectedWithLidOpen_returnsNil() {
        prefs.targetMicrophoneUID = "EXT"
        let result = selector.determineTargetDeviceUID(
            lidIsOpen: true,
            isExternalDisplayConnected: true,
            preferences: prefs,
            currentDefaultDeviceID: nil,
            fallbackDeviceID: nil
        )
        XCTAssertNil(result)
    }
}

// Simple in-memory mock for PreferenceManaging protocol for DefaultDeviceSelectorTests
class MockSelectorPrefs: PreferenceManaging {
    var targetMicrophoneUID: String?
    var revertToFallbackOnLidOpen: Bool = false
    var showNotifications: Bool = false
}
