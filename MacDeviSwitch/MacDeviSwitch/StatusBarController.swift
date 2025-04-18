import AppKit
import SwiftUI
import os.log
import MacDeviSwitchKit

class StatusBarController {
    private var statusItem: NSStatusItem!
    private let logger = Logger(subsystem: "via.MacDeviSwitch", category: "StatusBarController")

    // Dependencies (passed from AppDelegate)
    private let audioDeviceMonitor: AudioDeviceMonitoring
    private var preferenceManager: PreferenceManaging
    private var switchController: SwitchController?
    
    // UI Components
    private var deviceMenuItems: [NSMenuItem] = []
    private var preferencesWindow: PreferencesWindow?

    init(audioDeviceMonitor: AudioDeviceMonitoring, preferenceManager: PreferenceManaging, switchController: SwitchController? = nil) {
        self.audioDeviceMonitor = audioDeviceMonitor
        self.preferenceManager = preferenceManager
        self.switchController = switchController
        logger.debug("Initializing StatusBarController")

        setupStatusItem()
        // Initial menu build
        updateMenu()
        
        // Initialize preferences window
        self.preferencesWindow = PreferencesWindow(audioDeviceMonitor: audioDeviceMonitor, preferenceManager: preferenceManager)

        // Register for notifications to update menu dynamically
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenu),
            name: NSNotification.Name("AudioDevicesChanged"),
            object: nil
        )
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

        // --- Current Device Section ---
        // TODO: Get actual current default device from AudioSwitcher or monitor
        menu.addItem(NSMenuItem(title: "Current: System Default", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        // --- Target Device Selection ---
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

        // --- Settings ---
        let revertItem = NSMenuItem(title: "Revert to Internal on Lid Open", action: #selector(toggleRevertPreference(_:)), keyEquivalent: "")
        revertItem.target = self
        revertItem.state = preferenceManager.revertToFallbackOnLidOpen ? .on : .off
        menu.addItem(revertItem)
        
        // --- Preferences ---
        menu.addItem(NSMenuItem.separator())
        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        // --- Diagnostic Menu Items ---
        menu.addItem(NSMenuItem.separator())
        
        let diagnosticItem = NSMenuItem(title: "Diagnostic Info", action: #selector(showDiagnosticInfo(_:)), keyEquivalent: "")
        diagnosticItem.target = self
        menu.addItem(diagnosticItem)
        
        let forceSwitchItem = NSMenuItem(title: "Force Switch", action: #selector(forceSwitch(_:)), keyEquivalent: "")
        forceSwitchItem.target = self
        menu.addItem(forceSwitchItem)

        menu.addItem(NSMenuItem.separator())

        // --- Quit ---
        let quitItem = NSMenuItem(title: "Quit MacDeviSwitch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

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
        
        // Trigger the SwitchController to re-evaluate immediately
        do {
            let switchOccurred = try switchController?.evaluateAndSwitch() ?? false
            logger.debug("Switch result: \(switchOccurred ? "switched" : "no change needed")")
        } catch {
            logger.error("Error during evaluation: \(error.localizedDescription)")
        }
    }

    @objc private func toggleRevertPreference(_ sender: NSMenuItem) {
        let newState = !preferenceManager.revertToFallbackOnLidOpen
        logger.info("User toggled 'Revert on Lid Open' to: \(newState)")
        preferenceManager.revertToFallbackOnLidOpen = newState
        sender.state = newState ? .on : .off
    }
    
    @objc private func openPreferences(_ sender: NSMenuItem) {
        logger.info("Opening preferences window")
        preferencesWindow?.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
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

    @objc private func showDiagnosticInfo(_ sender: NSMenuItem) {
        logger.info("Diagnostic info requested.")
        
        // Run diagnostic if SwitchController is available
        if let switchController = switchController {
            switchController.diagnoseAudioSwitchingIssues()
            logger.info("Diagnostic information has been printed to the console")
        }
    }

    @objc private func forceSwitch(_ sender: NSMenuItem) {
        logger.info("Force switch requested.")
        
        // Check if target microphone is set
        guard let targetUID = preferenceManager.targetMicrophoneUID else {
            logger.warning("No target microphone selected")
            return
        }
        
        // Find target device name for better UX
        let availableInputs = audioDeviceMonitor.availableInputDevices
        let targetName = availableInputs.first(where: { $0.uid == targetUID })?.name ?? "Unknown Device"
        
        // Attempt to force switch
        if let switchController = switchController {
            let success = switchController.forceAudioDeviceSwitch()
            
            if success {
                logger.info("Successfully switched to \(targetName)")
            } else {
                logger.error("Failed to switch to \(targetName)")
            }
        } else {
            logger.error("SwitchController is not available. Cannot force switch.")
        }
    }

    // Clean up observer if using NotificationCenter
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
