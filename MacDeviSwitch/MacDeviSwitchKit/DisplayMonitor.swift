import Foundation
import CoreGraphics
import os.log

public final class DisplayMonitor: DisplayMonitoring {
    fileprivate let logger = Logger(subsystem: "com.yourcompany.macdeviswitchkit", category: "DisplayMonitor") // Replace with your bundle ID

    // Current state - reflects if at least one non-builtin display is connected
    public private(set) var isExternalDisplayConnected: Bool = false
    
    // Callback for display connection changes
    public var onDisplayConnectionChange: ((Bool) -> Void)?
    
    // Monitoring state
    private var isMonitoring: Bool = false

    public init() {
        logger.debug("Initializing DisplayMonitor")
        // Initial check
        updateExternalDisplayStatus()
    }

    deinit {
        logger.debug("Deinitializing DisplayMonitor")
        stopMonitoring()
    }
    
    public func startMonitoring() {
        guard !isMonitoring else { return }
        logger.debug("Starting display monitoring")
        registerForDisplayChanges()
        isMonitoring = true
    }
    
    public func stopMonitoring() {
        guard isMonitoring else { return }
        logger.debug("Stopping display monitoring")
        unregisterForDisplayChanges()
        isMonitoring = false
    }

    private func registerForDisplayChanges() {
        logger.debug("Registering for display reconfiguration notifications.")
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    private func unregisterForDisplayChanges() {
        logger.debug("Unregistering for display reconfiguration notifications.")
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    fileprivate func updateExternalDisplayStatus() {
        var onlineDisplays: UInt32 = 0
        var activeDisplays: [CGDirectDisplayID] = []

        // Get count of online displays
        guard CGGetOnlineDisplayList(0, nil, &onlineDisplays) == .success else {
            logger.error("Failed to get online display count.")
            // Consider the state unknown or unchanged? Defaulting to previous state for now.
            return
        }

        if onlineDisplays == 0 {
            logger.debug("No online displays found.")
            setExternalDisplayConnected(false)
            return
        }

        // Allocate space and get the list of online display IDs
        activeDisplays = Array<CGDirectDisplayID>(repeating: kCGNullDirectDisplay, count: Int(onlineDisplays))
        guard CGGetOnlineDisplayList(onlineDisplays, &activeDisplays, &onlineDisplays) == .success else {
             logger.error("Failed to get online display list.")
             return
        }

        // Check if any display is NOT built-in
        var foundExternal = false
        for displayID in activeDisplays where displayID != kCGNullDirectDisplay {
            if CGDisplayIsBuiltin(displayID) == 0 { // 0 means it's NOT built-in
                foundExternal = true
                logger.debug("Found external display with ID: \(displayID)")
                break // Found one, no need to check further
            }
        }

        setExternalDisplayConnected(foundExternal)
    }

    private func setExternalDisplayConnected(_ isConnected: Bool) {
        if self.isExternalDisplayConnected != isConnected {
            logger.info("External display connection status changed: \(isConnected ? "Connected" : "Disconnected")")
            self.isExternalDisplayConnected = isConnected
            onDisplayConnectionChange?(isConnected)
        }
    }
}

// C-style callback function
private func displayReconfigurationCallback(display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags, userInfo: UnsafeMutableRawPointer?) {
    guard let monitor = userInfo.map({ Unmanaged<DisplayMonitor>.fromOpaque($0).takeUnretainedValue() }) else {
        os_log(.error, "Display reconfiguration callback invoked without valid userInfo.")
        return
    }

    let logger = monitor.logger // Use instance logger

    // Check for significant changes (display added/removed)
    // While other flags exist (like resolution change), we primarily care about connection status for this app.
    if flags.contains(.addFlag) || flags.contains(.removeFlag) || flags.contains(.beginConfigurationFlag) {
        logger.debug("Received display reconfiguration event (flags: \(flags.rawValue)). Re-evaluating display status.")
        // Re-query the display list to update the status
        monitor.updateExternalDisplayStatus()
    } else {
        logger.debug("Received minor display reconfiguration event (flags: \(flags.rawValue)). Ignoring.")
    }
}
