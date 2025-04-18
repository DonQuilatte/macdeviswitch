import Foundation
import CoreAudio
import os.log

/// Controls audio device switching based on lid state and display connections
public final class SwitchController: SwitchControlling {
    private let logger = Logger(subsystem: "com.yourcompany.macdeviswitchkit", category: "SwitchController")

    private var lidMonitor: LidStateMonitoring
    private var displayMonitor: DisplayMonitoring
    private var audioDeviceMonitor: AudioDeviceMonitoring
    private let audioSwitcher: AudioSwitching
    private let preferences: PreferenceManaging

    // Store the UID of the mic that was active before switching to external
    private var fallbackMicrophoneUID: String? = nil
    private var fallbackMicrophoneID: AudioDeviceID? = nil // Store ID too for quicker revert
    
    // Optional notification manager for user feedback
    private var notificationManager: NotificationManaging?

    /// Initialize the SwitchController with required dependencies
    /// - Parameters:
    ///   - lidMonitor: The lid state monitoring component
    ///   - displayMonitor: The display monitoring component
    ///   - audioDeviceMonitor: The audio device monitoring component
    ///   - audioSwitcher: The audio switching component
    ///   - preferences: The preference management component
    public init(
        lidMonitor: LidStateMonitoring,
        displayMonitor: DisplayMonitoring,
        audioDeviceMonitor: AudioDeviceMonitoring,
        audioSwitcher: AudioSwitching,
        preferences: PreferenceManaging
    ) {
        self.lidMonitor = lidMonitor
        self.displayMonitor = displayMonitor
        self.audioDeviceMonitor = audioDeviceMonitor
        self.audioSwitcher = audioSwitcher
        self.preferences = preferences
        logger.debug("Initializing SwitchController")
    }
    
    /// Set the notification manager for user feedback
    /// - Parameter manager: The notification manager instance
    public func setNotificationManager(_ manager: NotificationManaging) {
        self.notificationManager = manager
    }

    /// Start the controller and perform initial evaluation
    public func start() {
        logger.info("Starting SwitchController monitoring.")
        // Perform an initial evaluation
        evaluateAndSwitch()
    }

    /// Start monitoring all relevant state changes
    public func startMonitoring() {
        logger.debug("Starting monitoring")
        
        // Set up lid state change handler
        lidMonitor.onLidStateChange = { [weak self] isOpen in
            guard let self = self else { return }
            self.logger.info("Lid state changed: \(isOpen ? "open" : "closed")")
            self.evaluateAndSwitch()
        }
        
        // Set up display connection change handler
        displayMonitor.onDisplayConnectionChange = { [weak self] isConnected in
            guard let self = self else { return }
            self.logger.info("Display connection changed: \(isConnected ? "connected" : "disconnected")")
            self.evaluateAndSwitch()
        }
        
        // Start individual monitors
        lidMonitor.startMonitoring()
        displayMonitor.startMonitoring()
        audioDeviceMonitor.startMonitoring()
        
        // Perform an initial evaluation
        evaluateAndSwitch()
    }

    /// Stop monitoring all state changes
    public func stopMonitoring() {
        logger.debug("Stopping monitoring")
        
        lidMonitor.stopMonitoring()
        displayMonitor.stopMonitoring()
        audioDeviceMonitor.stopMonitoring()
        
        // Remove callbacks
        lidMonitor.onLidStateChange = nil
        displayMonitor.onDisplayConnectionChange = nil
    }

    /// Evaluate current conditions and switch audio devices if necessary
    /// - Returns: Boolean indicating if a switch occurred
    @discardableResult
    public func evaluateAndSwitch() -> Bool {
        // Get current state
        let lidClosed = !lidMonitor.isLidOpen
        let externalDisplayConnected = displayMonitor.isExternalDisplayConnected
        
        print("Evaluating conditions - Lid closed: \(lidClosed), External display: \(externalDisplayConnected)")
        
        // Get target microphone UID from preferences
        guard let targetUID = preferences.targetMicrophoneUID else {
            print("No target microphone set in preferences. Skipping evaluation.")
            return false
        }
        
        // Get available devices
        let availableDevices = audioDeviceMonitor.availableInputDevices
        
        // Find target device in available devices
        guard let targetDevice = availableDevices.first(where: { $0.uid == targetUID }) else {
            print("⚠️ Target microphone not found in available devices. UID: \(targetUID)")
            print("Available devices: \(availableDevices.map { "\($0.name) (UID: \($0.uid))" }.joined(separator: ", "))")
            
            // Notify user that target device is not available
            notificationManager?.sendNotification(
                title: "Switch Failed",
                body: "Target microphone not available"
            )
            return false
        }
        
        // Get current default device
        guard let currentDeviceID = audioSwitcher.getDefaultInputDeviceID() else {
            print("⚠️ Failed to get current default input device")
            return false
        }
        
        // Log current device info
        if let currentDevice = availableDevices.first(where: { $0.id == currentDeviceID }) {
            print("Current input device: \(currentDevice.name) (ID: \(currentDevice.id), UID: \(currentDevice.uid))")
        } else {
            print("Current input device ID: \(currentDeviceID) (not found in available devices)")
        }
        
        // Check if we need to switch to target microphone
        // Condition: Lid closed with external display connected
        let shouldSwitchToTarget = lidClosed && externalDisplayConnected
        
        // Check if we need to revert to internal microphone
        // Condition: (Lid open AND revert preference enabled) OR (no external display AND revert preference enabled)
        let shouldRevertToInternal = ((!lidClosed) && preferences.revertOnLidOpen) || (!externalDisplayConnected && preferences.revertOnLidOpen)
        
        // Debug info
        print("Should switch to target: \(shouldSwitchToTarget)")
        print("Should revert to internal: \(shouldRevertToInternal)")
        
        // Store current device as fallback if we're about to switch
        if shouldSwitchToTarget && currentDeviceID != targetDevice.id {
            if let currentDevice = availableDevices.first(where: { $0.id == currentDeviceID }) {
                fallbackMicrophoneUID = currentDevice.uid
                fallbackMicrophoneID = currentDevice.id
                print("Stored fallback device: \(currentDevice.name) (ID: \(currentDevice.id))")
            }
        }
        
        // Perform the switch if needed
        if shouldSwitchToTarget && currentDeviceID != targetDevice.id {
            print("Switching to target microphone: \(targetDevice.name)")
            let success = audioSwitcher.setDefaultInputDevice(deviceID: targetDevice.id)
            
            if success {
                print("✅ Successfully switched to \(targetDevice.name)")
                notificationManager?.sendNotification(
                    title: "Audio Input Changed",
                    body: "Switched to \(targetDevice.name)"
                )
                return true
            } else {
                print("❌ Failed to switch to \(targetDevice.name)")
                notificationManager?.sendNotification(
                    title: "Switch Failed",
                    body: "Could not switch to \(targetDevice.name)"
                )
                
                // Clear fallback if switch failed
                fallbackMicrophoneUID = nil
                fallbackMicrophoneID = nil
                return false
            }
        } else if shouldRevertToInternal && fallbackMicrophoneID != nil && currentDeviceID != fallbackMicrophoneID {
            // Only revert if we have a fallback device stored
            if let fallbackID = fallbackMicrophoneID,
               let fallbackDevice = availableDevices.first(where: { $0.id == fallbackID }) {
                print("Reverting to fallback microphone: \(fallbackDevice.name)")
                let success = audioSwitcher.setDefaultInputDevice(deviceID: fallbackID)
                
                if success {
                    print("✅ Successfully reverted to \(fallbackDevice.name)")
                    notificationManager?.sendNotification(
                        title: "Audio Input Changed",
                        body: "Reverted to \(fallbackDevice.name)"
                    )
                    
                    // Clear fallback state after successful revert
                    fallbackMicrophoneUID = nil
                    fallbackMicrophoneID = nil
                    return true
                } else {
                    print("❌ Failed to revert to \(fallbackDevice.name)")
                    notificationManager?.sendNotification(
                        title: "Revert Failed",
                        body: "Could not revert to \(fallbackDevice.name)"
                    )
                    return false
                }
            } else {
                print("⚠️ No valid fallback device found for reverting")
                return false
            }
        } else {
            print("No audio device switch needed")
            return false
        }
    }

    /// Diagnose audio device switching issues
    /// Logs comprehensive diagnostic information about the current state
    public func diagnoseAudioSwitchingIssues() {
        // Log current state
        let lidOpen = lidMonitor.isLidOpen
        let externalDisplayConnected = displayMonitor.isExternalDisplayConnected
        let targetMicUID = preferences.targetMicrophoneUID
        
        print("\n\n========== MacDeviSwitch Diagnostic Information ==========")
        print("TIMESTAMP: \(Date())")
        print("\n--- CURRENT STATE ---")
        print("• Lid open: \(lidOpen)")
        print("• External display connected: \(externalDisplayConnected)")
        print("• Target microphone UID: \(targetMicUID ?? "None")")
        print("• Revert on lid open: \(preferences.revertOnLidOpen)")
        print("• Fallback microphone UID: \(fallbackMicrophoneUID ?? "None")")
        
        // Log available devices
        let availableDevices = audioDeviceMonitor.availableInputDevices
        print("\n--- AVAILABLE INPUT DEVICES ---")
        if availableDevices.isEmpty {
            print("• No input devices available!")
        } else {
            for device in availableDevices {
                print("• \(device.name) (ID: \(device.id), UID: \(device.uid))")
            }
        }
        
        // Log current device
        print("\n--- CURRENT INPUT DEVICE ---")
        if let currentDeviceID = audioSwitcher.getDefaultInputDeviceID() {
            if let currentDevice = availableDevices.first(where: { $0.id == currentDeviceID }) {
                print("• Current input device: \(currentDevice.name) (ID: \(currentDevice.id), UID: \(currentDevice.uid))")
            } else {
                print("• Current input device ID: \(currentDeviceID) (not found in available devices)")
            }
        } else {
            print("• Failed to get current default input device")
        }
        
        // Check switching conditions
        print("\n--- SWITCHING ANALYSIS ---")
        
        // Case 1: Lid closed with external display
        if !lidOpen && externalDisplayConnected {
            print("• Condition MATCHED: Lid closed with external display connected")
            
            // Check if we have a target microphone set
            if let targetUID = targetMicUID {
                print("• Target microphone set: \(targetUID)")
                
                // Find the target device in available devices
                if let targetDevice = availableDevices.first(where: { $0.uid == targetUID }) {
                    print("• Target microphone \(targetDevice.name) found in available devices")
                    
                    // Check if we're already using the target device
                    if let currentDeviceID = audioSwitcher.getDefaultInputDeviceID(),
                       targetDevice.id == currentDeviceID {
                        print("• Already using target microphone \(targetDevice.name)")
                        print("  → No switch needed")
                    } else {
                        print("• Not currently using target microphone")
                        print("  → Switch should occur but didn't")
                        print("  → Check if SwitchController.evaluateAndSwitch() was called")
                    }
                } else {
                    print("• Target microphone with UID \(targetUID) NOT found in available devices")
                    print("  → This is preventing the switch")
                    print("  → Available UIDs: \(availableDevices.map { $0.uid }.joined(separator: ", "))")
                }
            } else {
                print("• No target microphone set")
                print("  → This is preventing the switch")
                print("  → Set a target microphone in preferences")
            }
        } else {
            print("• Condition NOT MATCHED: Lid closed with external display connected")
            if lidOpen {
                print("  → Lid is open")
            }
            if !externalDisplayConnected {
                print("  → No external display connected")
            }
        }
        
        // Case 2: Lid opened with fallback device
        if lidOpen && preferences.revertOnLidOpen && fallbackMicrophoneUID != nil {
            print("\n• Condition MATCHED: Lid open with fallback device available")
            
            if let fallbackUID = fallbackMicrophoneUID, 
               let fallbackDevice = availableDevices.first(where: { $0.uid == fallbackUID }) {
                print("• Fallback microphone \(fallbackDevice.name) found in available devices")
                
                // Check if we're currently using the target device
                if let currentDeviceID = audioSwitcher.getDefaultInputDeviceID(),
                   let targetUID = targetMicUID,
                   let targetDevice = availableDevices.first(where: { $0.uid == targetUID }),
                   targetDevice.id == currentDeviceID {
                    print("• Currently using target microphone \(targetDevice.name)")
                    print("  → Revert should occur but didn't")
                    print("  → Check if SwitchController.evaluateAndSwitch() was called")
                } else {
                    print("• Not using target device, not reverting")
                }
            } else {
                print("• Fallback microphone not found in available devices")
                print("  → This is preventing the revert")
            }
        }
        
        print("\n--- MONITORING STATUS ---")
        print("• LidStateMonitor isMonitoring: \(lidMonitor is LidStateMonitoring ? "Active" : "Unknown")")
        print("• DisplayMonitor isMonitoring: \(displayMonitor is DisplayMonitoring ? "Active" : "Unknown")")
        
        print("\n==========================================================\n")
    }

    /// Force a switch to the target microphone for testing purposes
    /// - Returns: Boolean indicating if the switch was successful
    public func forceAudioDeviceSwitch() -> Bool {
        print("\n\n========== FORCE AUDIO DEVICE SWITCH TEST ==========")
        print("TIMESTAMP: \(Date())")
        
        // Get target microphone UID from preferences
        guard let targetUID = preferences.targetMicrophoneUID else {
            print("❌ ERROR: No target microphone set in preferences")
            print("   Please set a target microphone in the app preferences")
            print("=================================================\n")
            
            notificationManager?.sendNotification(
                title: "Switch Failed",
                body: "No target microphone set in preferences"
            )
            return false
        }
        
        print("• Target microphone UID: \(targetUID)")
        
        // Get available devices
        let availableDevices = audioDeviceMonitor.availableInputDevices
        print("• Available input devices: \(availableDevices.count)")
        for device in availableDevices {
            print("  - \(device.name) (ID: \(device.id), UID: \(device.uid))")
        }
        
        // Find target device in available devices
        guard let targetDevice = availableDevices.first(where: { $0.uid == targetUID }) else {
            print("❌ ERROR: Target microphone not found in available devices")
            print("   Available UIDs: \(availableDevices.map { $0.uid }.joined(separator: ", "))")
            print("=================================================\n")
            
            notificationManager?.sendNotification(
                title: "Switch Failed",
                body: "Target microphone not found in available devices"
            )
            return false
        }
        
        print("• Found target device: \(targetDevice.name) (ID: \(targetDevice.id))")
        
        // Get current default device
        guard let currentDeviceID = audioSwitcher.getDefaultInputDeviceID() else {
            print("❌ ERROR: Failed to get current default input device")
            print("=================================================\n")
            
            notificationManager?.sendNotification(
                title: "Switch Failed",
                body: "Failed to get current default input device"
            )
            return false
        }
        
        if let currentDevice = availableDevices.first(where: { $0.id == currentDeviceID }) {
            print("• Current input device: \(currentDevice.name) (ID: \(currentDevice.id), UID: \(currentDevice.uid))")
            
            // Store as fallback
            fallbackMicrophoneUID = currentDevice.uid
            fallbackMicrophoneID = currentDevice.id
            print("• Stored fallback device: \(currentDevice.name)")
        } else {
            print("• Current input device ID: \(currentDeviceID) (not found in available devices)")
        }
        
        // Check if already using target device
        if currentDeviceID == targetDevice.id {
            print("✓ Already using target microphone \(targetDevice.name)")
            print("=================================================\n")
            return true
        }
        
        // Attempt to switch
        print("• Attempting to switch to \(targetDevice.name)...")
        let success = audioSwitcher.setDefaultInputDevice(deviceID: targetDevice.id)
        
        if success {
            print("✓ SUCCESS: Switched to \(targetDevice.name)")
            
            // Verify the switch
            if let newDefaultID = audioSwitcher.getDefaultInputDeviceID(),
               let newDevice = availableDevices.first(where: { $0.id == newDefaultID }) {
                print("• Verified new default device: \(newDevice.name) (ID: \(newDevice.id))")
            } else {
                print("⚠️ WARNING: Could not verify new default device")
            }
            
            notificationManager?.sendNotification(
                title: "Audio Input Changed",
                body: "Switched to \(targetDevice.name)"
            )
        } else {
            print("❌ ERROR: Failed to switch to \(targetDevice.name)")
            
            // Clear fallback if switch failed
            fallbackMicrophoneUID = nil
            fallbackMicrophoneID = nil
            
            notificationManager?.sendNotification(
                title: "Switch Failed",
                body: "Could not switch to \(targetDevice.name)"
            )
        }
        
        print("=================================================\n")
        return success
    }
    
    /// Force a revert to the fallback microphone for testing purposes
    /// - Returns: Boolean indicating if the revert was successful
    public func forceRevertToFallback() -> Bool {
        print("\n\n========== FORCE REVERT TO FALLBACK TEST ==========")
        print("TIMESTAMP: \(Date())")
        
        // Check if we have a fallback device stored
        guard let fallbackID = fallbackMicrophoneID else {
            print("❌ ERROR: No fallback device stored")
            print("   You must first switch to a target device to store a fallback")
            print("=================================================\n")
            
            notificationManager?.sendNotification(
                title: "Revert Failed",
                body: "No fallback device stored"
            )
            return false
        }
        
        print("• Fallback microphone ID: \(fallbackID)")
        
        // Get available devices
        let availableDevices = audioDeviceMonitor.availableInputDevices
        print("• Available input devices: \(availableDevices.count)")
        
        // Check if fallback device is still available
        guard let fallbackDevice = availableDevices.first(where: { $0.id == fallbackID }) else {
            print("❌ ERROR: Fallback device no longer available")
            print("   Available devices: \(availableDevices.map { $0.name }.joined(separator: ", "))")
            print("=================================================\n")
            
            // Clear fallback state since device is no longer available
            fallbackMicrophoneUID = nil
            fallbackMicrophoneID = nil
            
            notificationManager?.sendNotification(
                title: "Revert Failed",
                body: "Fallback microphone no longer available"
            )
            return false
        }
        
        print("• Found fallback device: \(fallbackDevice.name) (ID: \(fallbackDevice.id))")
        
        // Get current default device
        guard let currentDeviceID = audioSwitcher.getDefaultInputDeviceID() else {
            print("❌ ERROR: Failed to get current default input device")
            print("=================================================\n")
            
            notificationManager?.sendNotification(
                title: "Revert Failed",
                body: "Failed to get current default input device"
            )
            return false
        }
        
        if let currentDevice = availableDevices.first(where: { $0.id == currentDeviceID }) {
            print("• Current input device: \(currentDevice.name) (ID: \(currentDevice.id), UID: \(currentDevice.uid))")
        } else {
            print("• Current input device ID: \(currentDeviceID) (not found in available devices)")
        }
        
        // Check if already using fallback device
        if currentDeviceID == fallbackID {
            print("✓ Already using fallback microphone \(fallbackDevice.name)")
            print("=================================================\n")
            return true
        }
        
        // Attempt to switch back to fallback device
        print("• Attempting to revert to \(fallbackDevice.name)...")
        let success = audioSwitcher.setDefaultInputDevice(deviceID: fallbackID)
        
        if success {
            print("✓ SUCCESS: Reverted to \(fallbackDevice.name)")
            
            // Verify the switch
            if let newDefaultID = audioSwitcher.getDefaultInputDeviceID(),
               let newDevice = availableDevices.first(where: { $0.id == newDefaultID }) {
                print("• Verified new default device: \(newDevice.name) (ID: \(newDevice.id))")
            } else {
                print("⚠️ WARNING: Could not verify new default device")
            }
            
            // Clear fallback state after successful revert
            fallbackMicrophoneUID = nil
            fallbackMicrophoneID = nil
            
            notificationManager?.sendNotification(
                title: "Audio Input Changed",
                body: "Reverted to \(fallbackDevice.name)"
            )
        } else {
            print("❌ ERROR: Failed to revert to \(fallbackDevice.name)")
            
            notificationManager?.sendNotification(
                title: "Revert Failed",
                body: "Could not revert to \(fallbackDevice.name)"
            )
        }
        
        print("=================================================\n")
        return success
    }
}