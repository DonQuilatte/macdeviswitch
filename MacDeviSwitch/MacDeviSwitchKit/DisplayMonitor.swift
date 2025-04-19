import Foundation
import CoreGraphics
import os.log

/// Errors that can occur during display monitoring
public enum DisplayMonitorError: Error, LocalizedError {
    case registrationFailed
    case displayListQueryFailed(CGError)

    public var errorDescription: String? {
        switch self {
        case .registrationFailed:
            return "Failed to register for display reconfiguration notifications"
        case .displayListQueryFailed(let error):
            return "Failed to query display list (Error: \(error))"
        }
    }
}

/// Detects external display connections via CGDisplay.
public final class DisplayMonitor: DisplayMonitoring {
    fileprivate let logger = Logger(subsystem: "via.MacDeviSwitch.kit", category: "DisplayMonitor")

    /// Indicates whether an external display is currently connected.
    public private(set) var isExternalDisplayConnected: Bool = false

    /// Callback invoked when the external display connection status changes.
    ///
    /// - Parameter isConnected: `true` if an external display is connected, `false` otherwise.
    public var onDisplayConnectionChange: ((Bool) -> Void)?

    // Monitoring state
    private var isMonitoring: Bool = false

    /// Initializes a new `DisplayMonitor` instance.
    public init() {
        logger.debug("Initializing DisplayMonitor")
        // Initial check
        updateExternalDisplayStatus()
    }

    deinit {
        logger.debug("Deinitializing DisplayMonitor")
        stopMonitoring()
    }

    /// Starts monitoring for display connection changes.
    ///
    /// If monitoring is already active, this method does nothing.
    public func startMonitoring() {
        guard !isMonitoring else { return }
        logger.debug("Starting display monitoring")
        do {
            try registerForDisplayChanges()
        } catch {
            logger.error("Failed to start monitoring: \(error)")
        }
        isMonitoring = true
    }

    /// Stops monitoring for display connection changes.
    ///
    /// If monitoring is not active, this method does nothing.
    public func stopMonitoring() {
        guard isMonitoring else { return }
        logger.debug("Stopping display monitoring")
        unregisterForDisplayChanges()
        isMonitoring = false
    }

    private func registerForDisplayChanges() throws {
        logger.debug("Registering for display reconfiguration notifications.")
        let error = CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback,
                                                             Unmanaged.passUnretained(self).toOpaque())
        if error != .success {
            throw DisplayMonitorError.registrationFailed
        }
    }

    private func unregisterForDisplayChanges() {
        logger.debug("Unregistering for display reconfiguration notifications.")
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback,
                                               Unmanaged.passUnretained(self).toOpaque())
    }

    fileprivate func updateExternalDisplayStatus() {
        var onlineDisplays: UInt32 = 0
        var activeDisplays: [CGDirectDisplayID] = []

        // Get count of online displays
        let error = CGGetOnlineDisplayList(0, nil, &onlineDisplays)
        guard error == .success else {
            logger.error("Failed to get online display count. Error: \(error.rawValue)")
            // Consider the state unknown or unchanged? Defaulting to previous state for now.
            return
        }

        if onlineDisplays == 0 {
            logger.debug("No online displays found.")
            setExternalDisplayConnected(false)
            return
        }

        // Allocate space and get the list of online display IDs
        activeDisplays = [CGDirectDisplayID](repeating: kCGNullDirectDisplay,
                                              count: Int(onlineDisplays))
        let listError = CGGetOnlineDisplayList(onlineDisplays, &activeDisplays, &onlineDisplays)
        guard listError == .success else {
             logger.error("Failed to get online display list. Error: \(listError.rawValue)")
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
private func displayReconfigurationCallback(display: CGDirectDisplayID,
                                            flags: CGDisplayChangeSummaryFlags,
                                            userInfo: UnsafeMutableRawPointer?) {
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
