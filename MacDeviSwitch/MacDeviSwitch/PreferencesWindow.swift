import Cocoa
import MacDeviSwitchKit

class PreferencesWindow: NSWindowController {
    // MARK: - Properties
    
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
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        guard let window = self.window else { return }
        
        let contentView = NSView(frame: window.contentView!.bounds)
        window.contentView = contentView
        
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
        revertToggle = NSButton(checkboxWithTitle: "Revert to Internal Mic on Lid Open", target: self, action: #selector(toggleRevertPreference(_:)))
        revertToggle.translatesAutoresizingMaskIntoConstraints = false
        revertToggle.state = preferenceManager.revertToFallbackOnLidOpen ? .on : .off
        contentView.addSubview(revertToggle)
        
        // Notifications Toggle
        notificationsToggle = NSButton(checkboxWithTitle: "Show Notifications for Device Changes", target: self, action: #selector(toggleNotifications(_:)))
        notificationsToggle.translatesAutoresizingMaskIntoConstraints = false
        // We'll need to add this preference to PreferenceManager
        notificationsToggle.state = .on // Default to on
        contentView.addSubview(notificationsToggle)
        
        // Save Button
        let saveButton = NSButton(title: "Save", target: self, action: #selector(savePreferences(_:)))
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.bezelStyle = .rounded
        contentView.addSubview(saveButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Title
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            // Target Label
            targetLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            targetLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            // Device Popup
            devicePopup.topAnchor.constraint(equalTo: targetLabel.bottomAnchor, constant: 8),
            devicePopup.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            devicePopup.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Revert Toggle
            revertToggle.topAnchor.constraint(equalTo: devicePopup.bottomAnchor, constant: 20),
            revertToggle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            // Notifications Toggle
            notificationsToggle.topAnchor.constraint(equalTo: revertToggle.bottomAnchor, constant: 12),
            notificationsToggle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            // Save Button
            saveButton.topAnchor.constraint(equalTo: notificationsToggle.bottomAnchor, constant: 20),
            saveButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            saveButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])
        
        // Populate device popup
        updateDevicePopup()
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
