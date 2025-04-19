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

    func testRevertToFallbackOnLidOpen_DefaultValue() {
        // Arrange: Defaults registered in init

        // Act
        let defaultValue = preferenceManager.revertToFallbackOnLidOpen

        // Assert
        // Default is true as per PreferenceManager implementation
        XCTAssertTrue(defaultValue, "Default value for revertToFallbackOnLidOpen should be true.")
    }

    func testRevertToFallbackOnLidOpen_SetToFalse() {
        // Arrange: Default is true

        // Act
        preferenceManager.revertToFallbackOnLidOpen = false
        let newValue = preferenceManager.revertToFallbackOnLidOpen

        // Assert
        XCTAssertFalse(newValue, "Value should be false after setting to false.")
        XCTAssertFalse(userDefaults.bool(forKey: "revertToFallbackOnLidOpen"), "UserDefaults should store false.")
    }

    func testRevertToFallbackOnLidOpen_SetToTrue() {
        // Arrange
        preferenceManager.revertToFallbackOnLidOpen = false // Start with false

        // Act
        preferenceManager.revertToFallbackOnLidOpen = true
        let newValue = preferenceManager.revertToFallbackOnLidOpen

        // Assert
        XCTAssertTrue(newValue, "Value should be true after setting to true.")
        XCTAssertTrue(userDefaults.bool(forKey: "revertToFallbackOnLidOpen"), "UserDefaults should store true.")
    }

    // MARK: - showNotifications Tests

    func testShowNotifications_DefaultValue() {
        // Arrange: Defaults registered in init

        // Act
        let defaultValue = preferenceManager.showNotifications

        // Assert
        // Default is true as per PreferenceManager implementation
        XCTAssertTrue(defaultValue, "Default value for showNotifications should be true.")
    }

    func testShowNotifications_SetToFalse() {
        // Arrange: Default is true

        // Act
        preferenceManager.showNotifications = false
        let newValue = preferenceManager.showNotifications

        // Assert
        XCTAssertFalse(newValue, "Value should be false after setting to false.")
        XCTAssertFalse(userDefaults.bool(forKey: "showNotifications"), "UserDefaults should store false.")
    }

    func testShowNotifications_SetToTrue() {
        // Arrange
        preferenceManager.showNotifications = false // Start with false

        // Act
        preferenceManager.showNotifications = true
        let newValue = preferenceManager.showNotifications

        // Assert
        XCTAssertTrue(newValue, "Value should be true after setting to true.")
        XCTAssertTrue(userDefaults.bool(forKey: "showNotifications"), "UserDefaults should store true.")
    }
}
