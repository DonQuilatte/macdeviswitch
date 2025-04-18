# MACDEVISWITCH PRODUCT REQUIREMENTS DOCUMENT

## 1. Objective

Automatically switch the macOS default audio input device between the internal microphone and a predefined external microphone based on lid open/close events when an external display is connected, eliminating manual adjustments for users in clamshell mode.

## 2. User Value

*   **Seamless Workflow:** Users docking/undocking MacBooks with external microphones avoid incorrect audio input during calls or recordings without manual intervention.
*   **Enhanced Reliability:** Reduces the likelihood of using the wrong microphone, improving audio quality in meetings and recordings.

## 3. User Stories

*   **3.1 (Clamshell Start):** As a MacBook user with an external display and USB microphone, when I close the lid (entering clamshell mode), I want the system to automatically select my designated external microphone so my audio input remains consistent and clear.
*   **3.2 (Clamshell End):** As the same user, when I open the lid (exiting clamshell mode), I want the system to automatically switch back to the internal microphone (if configured to do so) so I can use the laptop standalone without interruption.
*   **3.3 (Manual Override):** As a user, I want to manually select my preferred external microphone from a list of connected devices via the menu bar icon.
*   **3.4 (Clear Feedback):** As a user, I want clear, unobtrusive confirmation when an automatic switch occurs and informative error messages if a switch fails.

## 4. Functional Requirements

### 4.1 Core Logic & Device Handling

*   **4.1.1 Prerequisites for Auto-Switching:**
    *   An external display must be connected.
    *   A target external microphone's Unique Identifier (UID) must be selected and stored by the user.
    *   The selected target microphone must be connected and detectable by the system.
*   **4.1.2 Lid Close Event (Entering Clamshell):**
    *   Verify prerequisites (4.1.1).
    *   If the current default input is *not* the target microphone, store the current input's UID as the 'fallback' device.
    *   Switch the system's default audio input to the target microphone.
*   **4.1.3 Lid Open Event (Exiting Clamshell):**
    *   Verify the current default input *is* the target microphone.
    *   Verify a valid 'fallback' microphone UID is stored.
    *   Check the user preference (`RevertToFallbackOnLidOpen`).
    *   If `RevertToFallbackOnLidOpen` is `true`:
        *   Switch the system's default audio input to the fallback microphone.
    *   If `RevertToFallbackOnLidOpen` is `false`:
        *   Do nothing (leave the target microphone selected).
*   **4.1.4 Device Detection:** The application must monitor for connections/disconnections of audio devices and update the available device list accordingly.

### 4.2 User Interface (Status Bar Menu)

*   **4.2.1 Menu Items:**
    *   Display the currently active default microphone name with a checkmark (`NSMenuItem.state = .on`).
    *   Separator.
    *   Header: "Select Target External Mic:"
    *   List of all currently connected *input* audio devices. The selected target device should have a persistent indicator (e.g., a different symbol or sub-checkmark). Selecting a device updates the stored target UID.
    *   Separator.
    *   Toggle Item: "Revert to Internal Mic on Lid Open" (Reflects/updates `RevertToFallbackOnLidOpen` preference).
    *   Separator.
    *   Quit `macdeviswitch`.
*   **4.2.2 Icon Behavior:**
    *   Default state (e.g., grey icon).
    *   State 1: Target external microphone is active (e.g., green icon).
    *   State 2: Fallback (likely internal) microphone is active (e.g., orange icon).
    *   On successful automatic switch: Briefly flash the icon (e.g., cycle through states quickly for ~0.5s).

### 4.3 Persistence

*   **4.3.1 Target Microphone:** The UID of the user-selected target external microphone must be stored persistently (e.g., `UserDefaults`).
*   **4.3.2 Revert Preference:** The state of the "Revert to Internal Mic on Lid Open" toggle (`RevertToFallbackOnLidOpen`) must be stored persistently (e.g., `UserDefaults`).
*   **4.3.3 Fallback Microphone:** The UID of the fallback microphone is stored *transiently* during a session (only needed between lid close and lid open).

### 4.4 Feedback & Error Handling

*   **4.4.1 Success Notification:** On successful automatic switch, post a brief, low-priority `UNUserNotification` (e.g., "Switched mic to [Device Name]").
*   **4.4.2 Error Notification:** If an automatic switch fails (e.g., target device disconnected), post a standard-priority `UNUserNotification` explaining the issue (e.g., "Failed to switch mic: Target device '[Device Name]' not found.").
*   **4.4.3 Visual Feedback:** Use menu item checkmarks and status bar icon colour changes (see 4.2.1, 4.2.2).

## 5. Non-Functional Requirements

*   **Performance:** Audio switch completion time < 2 seconds. Idle CPU usage < 1%.
*   **Code Quality:** No build warnings, especially related to unsafe pointers ( resolved as of 18 April 2025). Adherence to Swift best practices.
*   **Testing:** Automated unit and integration tests run via CI (e.g., GitHub Actions) on every push. All tests must pass before merging.
*   **Compatibility:** macOS 15.0+.
*   **Distribution:** Application must be sandboxed, signed, and notarised for Mac App Store and/or independent distribution (DMG).

## 6. Architecture Overview

*   **Targets:**
    *   `MacDeviSwitchKit`: Framework/library containing core logic (monitoring, switching, device management).
    *   `MacDeviSwitch`: Main application target (GUI, AppDelegate, status bar integration).
*   **Key Components (`MacDeviSwitchKit`):**
    *   `LidStateMonitor`: Detects lid open/close events (e.g., via IOKit power management notifications).
    *   `DisplayMonitor`: Detects connection/disconnection of external displays (e.g., via `CGDisplayRegisterReconfigurationCallback`).
    *   `AudioDeviceMonitor`: Detects connection/disconnection of audio devices and retrieves device info (e.g., via CoreAudio `kAudioHardwarePropertyDevices`, `kAudioObjectPropertyListenerAdded/Removed`).
    *   `AudioSwitcher`: Handles changing the default system input device (CoreAudio façade).
    *   `PreferenceManager`: Manages persistent storage (`UserDefaults`).
    *   `SwitchController`: Orchestrates the logic based on events from monitors and preferences.
*   **App Layer (`MacDeviSwitch`):**
    *   `AppDelegate`: Composition root, sets up the status bar item, initializes `SwitchController` and other necessary app-level services.
    *   `StatusBarController`: Manages the `NSStatusItem` and its menu.
    *   `NotificationManager`: Handles posting `UNUserNotifications`.
*   **Design:** Dependency Injection using protocols for testability.

## 7. Technical Decisions

*   **CoreAudio:** Wrap complex CoreAudio APIs in a Swift-friendly façade (`AudioDeviceMonitor`, `AudioSwitcher`) to isolate C interactions.
*   **Event Handling:** Prioritize event-driven notifications (IOKit PM, CGDisplay, CoreAudio listeners) over polling for lid, display, and device changes. Use polling only as a last resort if event-based methods prove unreliable for specific scenarios.
*   **Logging:** Use `os_log` framework with a dedicated subsystem (e.g., `com.yourcompany.macdeviswitch`). Logs are for debugging, not user-facing.
*   **Concurrency:** Use appropriate concurrency mechanisms (e.g., async/await, Actors) for background monitoring tasks.

## 8. Success Metrics

*   **Accuracy:** ≥ 95% correct microphone selection across 100 representative lid open/close cycles with external display/mic connected.
*   **Stability:** Crash-free session rate ≥ 99% during testing (e.g., TestFlight over 30 days).
*   **Performance:** Average idle CPU usage < 1% (measured via Activity Monitor).
*   **User Satisfaction:** Post-launch user-reported issues related to incorrect switching < 1 per 100 active users.

## 9. Future Ideas (Out of Scope for MVP)

*   Support for a prioritized list of multiple external microphones.
*   "Launch at Login" preference.
*   Location-based profiles (different target mics for home/office).
*   Opt-in anonymous usage analytics.

## 10. Glossary

*   **UID:** Unique Identifier. A string assigned by CoreAudio to identify an audio device.
*   **Clamshell Mode:** MacBook operating with the lid closed while connected to an external display, keyboard, and mouse.
*   **Target Microphone:** The specific external microphone designated by the user for automatic switching.
*   **Fallback Microphone:** The microphone that was active *before* switching to the target (usually the internal microphone).
*   **MVP:** Minimum Viable Product.
