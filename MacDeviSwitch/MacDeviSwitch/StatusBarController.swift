import Cocoa
import os.log
import MacDeviSwitchKit
import UserNotifications

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

    init(
        audioDeviceMonitor: AudioDeviceMonitoring,
        preferenceManager: PreferenceManaging,
        switchController: SwitchController? = nil
    ) {
        self.audioDeviceMonitor = audioDeviceMonitor
        self.preferenceManager = preferenceManager
        self.switchController = switchController
        logger.debug("Initializing StatusBarController")

        setupStatusItem()
        // Initial menu build
        updateMenu()

        // Initialize preferences window
        self.preferencesWindow = PreferencesWindow(
            audioDeviceMonitor: audioDeviceMonitor,
            preferenceManager: preferenceManager
        )

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
        deviceMenuItems.removeAll() // Clear the cache before rebuilding
        logger.debug("Updating status bar menu.")

        // --- Current Device Section ---
        // Placeholder - needs dynamic update
        menu.addItem(NSMenuItem(title: "Current: System Default", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        // Build menu sections using helper functions
        buildDeviceMenuItems(menu: menu)
        buildSettingsMenuItems(menu: menu)
        buildActionMenuItems(menu: menu)

        logger.debug("Menu update complete.")
    }

    // MARK: - Menu Building Helpers

    private func buildDeviceMenuItems(menu: NSMenu) {
        menu.addItem(NSMenuItem(title: "Select Target External Mic:", action: nil, keyEquivalent: ""))

        let currentTargetUID = preferenceManager.targetMicrophoneUID
        let availableInputs = audioDeviceMonitor.availableInputDevices

        if availableInputs.isEmpty {
            menu.addItem(NSMenuItem(title: "No Input Devices Found", action: nil, keyEquivalent: ""))
        } else {
            for deviceInfo in availableInputs {
                let menuItem = NSMenuItem(
                    title: deviceInfo.name,
                    action: #selector(selectTargetDevice(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = deviceInfo // Store device info
                if deviceInfo.uid == currentTargetUID {
                    menuItem.state = .on // Checkmark
                }
                menu.addItem(menuItem)
                deviceMenuItems.append(menuItem) // Add to cache for checkmark updates
            }
        }
    }

    private func buildSettingsMenuItems(menu: NSMenu) {
        menu.addItem(NSMenuItem.separator())

        // --- Settings ---
        let revertItem = NSMenuItem(
            title: "Revert to Internal on Lid Open",
            action: #selector(toggleRevertPreference(_:)),
            keyEquivalent: ""
        )
        revertItem.target = self
        revertItem.state = preferenceManager.revertToFallbackOnLidOpen ? .on : .off
        menu.addItem(revertItem)
    }

    private func buildActionMenuItems(menu: NSMenu) {
        // --- Preferences ---
        menu.addItem(NSMenuItem.separator())
        let preferencesItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences(_:)),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        // --- Diagnostic Menu Items ---
        menu.addItem(NSMenuItem.separator())

        let diagnosticItem = NSMenuItem(
            title: "Diagnostic Info",
            action: #selector(showDiagnosticInfo(_:)),
            keyEquivalent: ""
        )
        diagnosticItem.target = self
        menu.addItem(diagnosticItem)

        let forceSwitchItem = NSMenuItem(
            title: "Force Switch",
            action: #selector(forceSwitch(_:)),
            keyEquivalent: ""
        )
        forceSwitchItem.target = self
        menu.addItem(forceSwitchItem)

        // --- Quit ---
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(
            title: "Quit MacDeviSwitch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
    }

    // MARK: - Menu Actions

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
        if switchController != nil {
            // Diagnostic API removed
            logger.info("Diagnostic information has been printed to the console")
        }

        // Attempt to open the diagnostic log file in user's Documents directory
        let fileManager = FileManager.default
        if let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let logFileURL = documentsDirectory.appendingPathComponent("macdeviswitch_diagnostics.log")
            if fileManager.fileExists(atPath: logFileURL.path) {
                NSWorkspace.shared.open(logFileURL)
                logger.info("Opened diagnostic log file at \(logFileURL.path)")
            } else {
                logger.error("Diagnostic log file not found at \(logFileURL.path)")
            }
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
            do {
                let switchOccurred = try switchController.evaluateAndSwitch()
                if switchOccurred {
                    logger.info("Successfully forced switch evaluation, device changed to \(targetName)")
                    showNotification(title: "Switch Attempted", body: "Switched to \(targetName)")
                } else {
                    logger.info("Successfully forced switch evaluation, device did not need to change from \(targetName)")
                    showNotification(title: "Switch Not Needed", body: "Already using \(targetName)")
                }
            } catch {
                logger.error("Error during forced switch evaluation: \(error.localizedDescription)")
                showNotification(title: "Error Forcing Switch", body: error.localizedDescription)
            }
        } else {
            logger.error("SwitchController is nil, cannot force switch.")
            showNotification(title: "Error", body: "Internal error: Switch controller not available.")
        }
    }

    // Helper to display notifications
    private func showNotification(title: String, body: String) {
        // Use UserNotifications framework for local notifications
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                // Log notification errors
                self?.logger.error("Notification error: \(error.localizedDescription)")
            }
        }
    }

    // Clean up observer if using NotificationCenter
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
