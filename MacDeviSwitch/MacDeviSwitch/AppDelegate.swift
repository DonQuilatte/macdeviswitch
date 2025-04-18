import Cocoa
import MacDeviSwitchKit
import os.log

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties
    
    // UI Components
    private var statusBarController: StatusBarController!
    private var preferencesWindow: PreferencesWindow?
    
    // MacDeviSwitchKit Components
    private var preferenceManager: PreferenceManaging!
    private var lidMonitor: LidStateMonitoring!
    private var displayMonitor: DisplayMonitoring!
    private var audioDeviceMonitor: AudioDeviceMonitoring!
    private var switchController: SwitchControlling!
    private var notificationManager: NotificationManaging!
    private var audioSwitcher: AudioSwitching!
    
    // Logging
    private let logger = Logger(subsystem: "via.MacDeviSwitch", category: "AppDelegate")
    private var logFileURL: URL?
    
    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create log file for diagnostics
        setupDiagnosticLogFile()
        
        // Setup components
        setupComponents()
        
        // Configure application menu
        configureApplicationMenu()
        
        // Hide the dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Start all monitoring components
        startMonitoring()
        
        // Schedule periodic diagnostics
        scheduleDiagnostics()
        
        #if DEBUG
        // Run initial diagnostics in debug mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.runInitialDiagnostics()
        }
        #endif
    }
    
    /// Sets up a diagnostic log file in the user's Documents directory
    private func setupDiagnosticLogFile() {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        logFileURL = documentsDirectory.appendingPathComponent("macdeviswitch_diagnostics.log")
        
        // Create or clear the log file
        if let url = logFileURL {
            do {
                try "=== MacDeviSwitch Diagnostic Log ===\nStarted: \(Date())\n\n".write(to: url, atomically: true, encoding: .utf8)
                logger.info("Diagnostic log file created at \(url.path)")
                print("Diagnostic log file created at \(url.path)")
            } catch {
                logger.error("Failed to create diagnostic log file: \(error.localizedDescription)")
                print("Failed to create diagnostic log file: \(error.localizedDescription)")
            }
        }
    }
    
    /// Initializes all components needed for the application
    private func setupComponents() {
        // --- Initialize MacDeviSwitchKit Components ---
        preferenceManager = PreferenceManager()
        lidMonitor = LidStateMonitor()
        displayMonitor = DisplayMonitor()
        audioDeviceMonitor = AudioDeviceMonitor()
        audioSwitcher = AudioSwitcher()
        
        // Initialize NotificationManager with PreferenceManager
        notificationManager = NotificationManager(preferenceManager: preferenceManager)
        
        // Initialize SwitchController with dependencies
        switchController = SwitchController(
            lidMonitor: lidMonitor,
            displayMonitor: displayMonitor,
            audioDeviceMonitor: audioDeviceMonitor,
            audioSwitcher: audioSwitcher,
            preferences: preferenceManager
        )
        
        // Set the notification manager
        switchController.setNotificationManager(notificationManager)
        
        // Initialize StatusBarController with dependencies
        statusBarController = StatusBarController(
            audioDeviceMonitor: audioDeviceMonitor,
            preferenceManager: preferenceManager,
            switchController: switchController as? SwitchController
        )
        
        // Initialize PreferencesWindow
        preferencesWindow = PreferencesWindow(
            audioDeviceMonitor: audioDeviceMonitor,
            preferenceManager: preferenceManager
        )
    }
    
    /// Configures the application menu to remove standard items
    private func configureApplicationMenu() {
        // Get the main menu
        guard let mainMenu = NSApp.mainMenu else { return }
        
        // Keep only the application menu (first item)
        if mainMenu.items.count > 1 {
            // Remove all menu items except the first one (Apple/Application menu)
            while mainMenu.items.count > 1 {
                mainMenu.removeItem(at: 1)
            }
            
            // Customize the application menu
            if let appMenu = mainMenu.items.first?.submenu {
                // Keep only About, Preferences, and Quit items
                let itemsToKeep = appMenu.items.filter { item in
                    let action = item.action
                    return action == #selector(NSApplication.orderFrontStandardAboutPanel(_:)) ||
                           action == #selector(NSApplication.terminate(_:)) ||
                           action == #selector(AppDelegate.openPreferences(_:)) ||
                           item.isSeparatorItem
                }
                
                appMenu.removeAllItems()
                
                // Add About item
                if let aboutItem = itemsToKeep.first(where: { $0.action == #selector(NSApplication.orderFrontStandardAboutPanel(_:)) }) {
                    appMenu.addItem(aboutItem)
                }
                
                appMenu.addItem(NSMenuItem.separator())
                
                // Add Preferences item
                if let preferencesItem = itemsToKeep.first(where: { $0.action == #selector(AppDelegate.openPreferences(_:)) }) {
                    appMenu.addItem(preferencesItem)
                }
                
                appMenu.addItem(NSMenuItem.separator())
                
                // Add Quit item
                if let quitItem = itemsToKeep.first(where: { $0.action == #selector(NSApplication.terminate(_:)) }) {
                    appMenu.addItem(quitItem)
                }
            }
        }
        
        logger.info("Application menu configured")
    }
    
    /// Opens the preferences window
    @IBAction func openPreferences(_ sender: Any) {
        logger.info("Opening preferences window from application menu")
        preferencesWindow?.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Starts all monitoring components
    private func startMonitoring() {
        // Start the controller (which will start all individual monitors)
        switchController.startMonitoring()
        
        writeToLogFile("All monitoring components started")
    }
    
    /// Schedules periodic diagnostic runs
    private func scheduleDiagnostics() {
        // Schedule diagnostics to run every hour
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.writeToLogFile("Running scheduled diagnostics...")
            
            if let controller = self?.switchController as? SwitchController {
                controller.diagnoseAudioSwitchingIssues()
            }
        }
    }
    
    /// Writes a message to the diagnostic log file
    /// - Parameter message: The message to write to the log
    private func writeToLogFile(_ message: String) {
        guard let url = logFileURL else { return }
        
        do {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium)
            let logMessage = "[\(timestamp)] \(message)\n"
            
            if let fileHandle = try? FileHandle(forWritingTo: url) {
                fileHandle.seekToEndOfFile()
                if let data = logMessage.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            }
        } catch {
            logger.error("Failed to write to log file: \(error.localizedDescription)")
        }
    }
    
    /// Runs initial diagnostics to verify the system state
    private func runInitialDiagnostics() {
        writeToLogFile("Running initial diagnostics...")
        
        // Run diagnostic on startup
        if let controller = switchController as? SwitchController {
            controller.diagnoseAudioSwitchingIssues()
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Stop all monitoring before terminating
        switchController.stopMonitoring()
        writeToLogFile("Application terminating, monitoring stopped")
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}