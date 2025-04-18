import XCTest
@testable import MacDeviSwitchKit // Import framework as @testable

class PreferenceManagerTests: XCTestCase {

    var userDefaults: UserDefaults!
    var preferenceManager: PreferenceManager!
    let suiteName = "TestUserDefaults"

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Use a temporary, volatile UserDefaults suite for testing
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName) // Clear before each test
        preferenceManager = PreferenceManager(userDefaults: userDefaults)
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        preferenceManager = nil
        try super.tearDownWithError()
    }

    func testTargetMicrophoneUID_SetAndGet() {
        // Arrange
        let testUID = "TestMic_UID_123"

        // Act
        preferenceManager.targetMicrophoneUID = testUID
        let retrievedUID = preferenceManager.targetMicrophoneUID

        // Assert
        XCTAssertEqual(retrievedUID, testUID, "Retrieved UID should match the set UID.")
        XCTAssertEqual(userDefaults.string(forKey: "targetMicrophoneUID"), testUID, "UserDefaults should store the correct UID.")
    }

    func testTargetMicrophoneUID_SetToNil() {
        // Arrange
        preferenceManager.targetMicrophoneUID = "SomeInitialUID"

        // Act
        preferenceManager.targetMicrophoneUID = nil
        let retrievedUID = preferenceManager.targetMicrophoneUID

        // Assert
        XCTAssertNil(retrievedUID, "Retrieved UID should be nil after setting to nil.")
        XCTAssertNil(userDefaults.string(forKey: "targetMicrophoneUID"), "UserDefaults value should be nil.")
    }

    func testTargetMicrophoneUID_GetWhenNotSet() {
        // Arrange: Nothing set in setUp's clear

        // Act
        let retrievedUID = preferenceManager.targetMicrophoneUID

        // Assert
        XCTAssertNil(retrievedUID, "Retrieved UID should be nil if never set.")
    }

    func testRevertOnLidOpen_DefaultValue() {
        // Arrange: Defaults registered in init

        // Act
        let defaultValue = preferenceManager.revertOnLidOpen

        // Assert
        // Default is true as per PreferenceManager implementation
        XCTAssertTrue(defaultValue, "Default value for revertOnLidOpen should be true.")
    }

    func testRevertOnLidOpen_SetToFalse() {
        // Arrange: Default is true

        // Act
        preferenceManager.revertOnLidOpen = false
        let newValue = preferenceManager.revertOnLidOpen

        // Assert
        XCTAssertFalse(newValue, "Value should be false after setting to false.")
        XCTAssertFalse(userDefaults.bool(forKey: "revertOnLidOpen"), "UserDefaults should store false.")
    }

    func testRevertOnLidOpen_SetToTrue() {
        // Arrange
        preferenceManager.revertOnLidOpen = false // Start with false

        // Act
        preferenceManager.revertOnLidOpen = true
        let newValue = preferenceManager.revertOnLidOpen

        // Assert
        XCTAssertTrue(newValue, "Value should be true after setting to true.")
        XCTAssertTrue(userDefaults.bool(forKey: "revertOnLidOpen"), "UserDefaults should store true.")
    }
}
