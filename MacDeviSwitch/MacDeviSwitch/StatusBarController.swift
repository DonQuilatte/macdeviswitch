import AppKit
import SwiftUI // Using SwiftUI for menu content eventually?
import os.log
import MacDeviSwitchKit // Import the framework

class StatusBarController {
    private var statusItem: NSStatusItem!
    private let logger = Logger(subsystem: "com.yourcompany.macdeviswitch", category: "StatusBarController") // Replace

    // Dependencies (passed from AppDelegate)
    private let audioDeviceMonitor: AudioDeviceMonitoring
    private var preferenceManager: PreferenceManaging
    // May need SwitchController later for status updates or manual actions

    // Keep track of device menu items to update checkmarks
    private var deviceMenuItems: [NSMenuItem] = []

    init(audioDeviceMonitor: AudioDeviceMonitoring, preferenceManager: PreferenceManaging) {
        self.audioDeviceMonitor = audioDeviceMonitor
        self.preferenceManager = preferenceManager
        logger.debug("Initializing StatusBarController")

        setupStatusItem()
        // Initial menu build
        updateMenu()

        // TODO: Register for notifications from monitors/controller to update menu dynamically
        // For now, menu is static after initial build. We'll need a way to refresh it.
        // e.g., NotificationCenter or Combine publishers from MacDeviSwitchKit components
        // NotificationCenter.default.addObserver(self, selector: #selector(updateMenu), name: .audioDevicesChanged, object: nil) // Example
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "MacDeviSwitch")
            // Consider changing icon based on state later
        }

        let menu = NSMenu()
        statusItem.menu = menu
        logger.debug("Status bar item created.")
    }

    // Call this to rebuild or update the menu contents
    @objc func updateMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()
        deviceMenuItems.removeAll()
        logger.debug("Updating status bar menu.")

        // --- Current Device Section (Placeholder) ---
        // TODO: Get actual current default device from AudioSwitcher or monitor
        menu.addItem(NSMenuItem(title: "Current: System Default", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        // --- Target Device Selection --- PRD 4.2.1
        menu.addItem(NSMenuItem(title: "Select Target External Mic:", action: nil, keyEquivalent: ""))

        let currentTargetUID = preferenceManager.targetMicrophoneUID
        let availableInputs = audioDeviceMonitor.availableInputDevices

        if availableInputs.isEmpty {
            menu.addItem(NSMenuItem(title: "No Input Devices Found", action: nil, keyEquivalent: ""))
        } else {
            for deviceInfo in availableInputs {
                let menuItem = NSMenuItem(title: deviceInfo.name, action: #selector(selectTargetDevice(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = deviceInfo // Store device info
                if deviceInfo.uid == currentTargetUID {
                    menuItem.state = .on // Checkmark
                }
                menu.addItem(menuItem)
                deviceMenuItems.append(menuItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // --- Settings --- PRD 4.2.1
        let revertItem = NSMenuItem(title: "Revert to Internal on Lid Open", action: #selector(toggleRevertPreference(_:)), keyEquivalent: "")
        revertItem.target = self
        revertItem.state = preferenceManager.revertOnLidOpen ? .on : .off
        menu.addItem(revertItem)

        menu.addItem(NSMenuItem.separator())

        // --- Quit --- PRD 4.2.1
        menu.addItem(NSMenuItem(title: "Quit MacDeviSwitch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        logger.debug("Menu update complete.")
    }

    @objc private func selectTargetDevice(_ sender: NSMenuItem) {
        guard let selectedDevice = sender.representedObject as? AudioDeviceInfo else {
            logger.error("Failed to get device info from menu item.")
            return
        }

        logger.info("User selected target device: \(selectedDevice.name) (UID: \(selectedDevice.uid))")
        preferenceManager.targetMicrophoneUID = selectedDevice.uid

        // Update checkmarks immediately
        updateMenuCheckmarks()

        // TODO: Trigger the SwitchController to re-evaluate immediately?
        // switchController.evaluateAndSwitch()
    }

    @objc private func toggleRevertPreference(_ sender: NSMenuItem) {
        let newState = !preferenceManager.revertOnLidOpen
        logger.info("User toggled 'Revert on Lid Open' to: \(newState)")
        preferenceManager.revertOnLidOpen = newState
        sender.state = newState ? .on : .off
    }

    // Helper to update only the checkmarks without rebuilding the whole menu
    private func updateMenuCheckmarks() {
         let currentTargetUID = preferenceManager.targetMicrophoneUID
         for item in deviceMenuItems {
             if let device = item.representedObject as? AudioDeviceInfo {
                 item.state = (device.uid == currentTargetUID) ? .on : .off
             }
         }
         logger.debug("Menu checkmarks updated.")
    }

    // Clean up observer if using NotificationCenter
    // deinit {
    //     NotificationCenter.default.removeObserver(self)
    // }
}
