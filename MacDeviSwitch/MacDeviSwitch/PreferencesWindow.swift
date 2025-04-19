import Cocoa
import MacDeviSwitchKit

class PreferencesWindow: NSWindowController {
    // MARK: - Properties

    private struct UIComponents {
        let titleLabel: NSTextField
        let targetLabel: NSTextField
        let saveButton: NSButton
    }

    private var audioDeviceMonitor: AudioDeviceMonitoring
    private var preferenceManager: PreferenceManaging

    private var devicePopup: NSPopUpButton!
    private var revertToggle: NSButton!
    private var notificationsToggle: NSButton!

    // MARK: - Initialization

    init(audioDeviceMonitor: AudioDeviceMonitoring, preferenceManager: PreferenceManaging) {
        self.audioDeviceMonitor = audioDeviceMonitor
        self.preferenceManager = preferenceManager

        // Create a window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacDeviSwitch Preferences"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        setupUI()
        updateDevicePopup() // Initial population

        // Add observer for device changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioDevicesChanged),
            name: .AudioDevicesChangedNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .AudioDevicesChangedNotification, object: nil)
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let window = self.window, let contentView = window.contentView else { return }

        let components = createUIComponents(contentView: contentView)
        setupLayoutConstraints(
            contentView: contentView,
            titleLabel: components.titleLabel,
            targetLabel: components.targetLabel,
            saveButton: components.saveButton
        )

        // Note: Observer added in init, no longer needed here.
    }

    /// Creates and adds UI components to the content view.
    /// - Parameter contentView: The view to add components to.
    /// - Returns: A `UIComponents` struct containing the created labels and button.
    private func createUIComponents(contentView: NSView) -> UIComponents {
        // Title Label
        let titleLabel = NSTextField(labelWithString: "MacDeviSwitch Preferences")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // Target Microphone Section
        let targetLabel = NSTextField(labelWithString: "Target External Microphone:")
        targetLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(targetLabel)

        devicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        devicePopup.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(devicePopup)

        // Revert Toggle
        revertToggle = NSButton(
            checkboxWithTitle: "Revert to Internal Mic on Lid Open",
            target: self,
            action: #selector(toggleRevertPreference(_:))
        )
        revertToggle.translatesAutoresizingMaskIntoConstraints = false
        revertToggle.state = preferenceManager.revertToFallbackOnLidOpen ? .on : .off
        contentView.addSubview(revertToggle)

        // Notifications Toggle
        notificationsToggle = NSButton(
            checkboxWithTitle: "Show Notifications for Device Changes",
            target: self,
            action: #selector(toggleNotifications(_:))
        )
        notificationsToggle.translatesAutoresizingMaskIntoConstraints = false
        notificationsToggle.state = .on // Default to on
        contentView.addSubview(notificationsToggle)

        // Save Button
        let saveButton = NSButton(title: "Save", target: self, action: #selector(savePreferences(_:)))
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.bezelStyle = .rounded
        contentView.addSubview(saveButton)

        return UIComponents(titleLabel: titleLabel, targetLabel: targetLabel, saveButton: saveButton)
    }

    /// Sets up the layout constraints for the UI components.
    /// - Parameters:
    ///   - contentView: The main content view.
    ///   - titleLabel: The title label.
    ///   - targetLabel: The target device label.
    ///   - saveButton: The save button.
    private func setupLayoutConstraints(
        contentView: NSView,
        titleLabel: NSTextField,
        targetLabel: NSTextField,
        saveButton: NSButton
    ) {
        // Title Constraints
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor)
        ])

        // Target Label Constraints
        NSLayoutConstraint.activate([
            targetLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            targetLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20)
        ])

        // Device Popup Constraints
        NSLayoutConstraint.activate([
            devicePopup.centerYAnchor.constraint(equalTo: targetLabel.centerYAnchor),
            devicePopup.leadingAnchor.constraint(equalTo: targetLabel.trailingAnchor, constant: 8),
            devicePopup.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20)
        ])

        // Revert Toggle Constraints
        NSLayoutConstraint.activate([
            revertToggle.topAnchor.constraint(equalTo: targetLabel.bottomAnchor, constant: 20),
            revertToggle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20)
        ])

        // Notifications Toggle Constraints
        NSLayoutConstraint.activate([
            notificationsToggle.topAnchor.constraint(equalTo: revertToggle.bottomAnchor, constant: 8),
            notificationsToggle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20)
        ])

        // Save Button Constraints
        NSLayoutConstraint.activate([
            saveButton.topAnchor.constraint(greaterThanOrEqualTo: notificationsToggle.bottomAnchor, constant: 30),
            saveButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            saveButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
        ])
    }

    // MARK: - UI Updates

    func updateDevicePopup() {
        devicePopup.removeAllItems()

        let availableInputs = audioDeviceMonitor.availableInputDevices
        let currentTargetUID = preferenceManager.targetMicrophoneUID

        if availableInputs.isEmpty {
            devicePopup.addItem(withTitle: "No Input Devices Found")
            devicePopup.isEnabled = false
        } else {
            devicePopup.isEnabled = true

            for deviceInfo in availableInputs {
                devicePopup.addItem(withTitle: deviceInfo.name)
                let menuItem = devicePopup.lastItem
                menuItem?.representedObject = deviceInfo

                if deviceInfo.uid == currentTargetUID {
                    devicePopup.select(menuItem)
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func toggleRevertPreference(_ sender: NSButton) {
        preferenceManager.revertToFallbackOnLidOpen = (sender.state == .on)
    }

    @objc private func toggleNotifications(_ sender: NSButton) {
        // We'll need to add this preference to PreferenceManager
        // preferenceManager.showNotifications = (sender.state == .on)
    }

    @objc private func savePreferences(_ sender: NSButton) {
        // Save target microphone selection
        if let selectedItem = devicePopup.selectedItem,
           let deviceInfo = selectedItem.representedObject as? AudioDeviceInfo {
            preferenceManager.targetMicrophoneUID = deviceInfo.uid
        }

        // Close window
        close()
    }

    @objc private func handleAudioDevicesChanged() {
        DispatchQueue.main.async {
            self.updateDevicePopup()
        }
    }

    // MARK: - Public Methods

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)

        // Update UI with current preferences
        updateDevicePopup()
        revertToggle.state = preferenceManager.revertToFallbackOnLidOpen ? .on : .off

        // Bring to front
        window?.makeKeyAndOrderFront(sender)
    }
}
