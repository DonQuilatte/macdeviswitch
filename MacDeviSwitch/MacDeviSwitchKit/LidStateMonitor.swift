import Foundation
import IOKit
import IOKit.pwr_mgt
import os.log

/// Errors that can occur during lid state monitoring
public enum LidStateMonitorError: Error, LocalizedError {
    /// Failed to register for system power notifications
    case registrationFailed
    /// Notification port is nil after registration
    case notificationPortNil
    /// Failed to deregister for system power notifications
    case deregistrationFailed
    /// Failed to close root power domain port
    case serviceCloseFailed
    /// Failed to query lid state
    case queryFailed
    
    public var errorDescription: String? {
        switch self {
        case .registrationFailed:
            return "Failed to register for system power notifications"
        case .notificationPortNil:
            return "Notification port is nil after registration"
        case .deregistrationFailed:
            return "Failed to deregister for system power notifications"
        case .serviceCloseFailed:
            return "Failed to close root power domain port"
        case .queryFailed:
            return "Failed to query lid state"
        }
    }
}

/// Detects lid open/close events via IOKit.
public final class LidStateMonitor: LidStateMonitoring {
    fileprivate let logger = Logger(subsystem: "via.MacDeviSwitch.kit", category: "LidStateMonitor")
    fileprivate var rootPort: io_connect_t = 0
    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = 0

    /// Indicates whether the lid is currently open.
    public private(set) var isLidOpen: Bool = true // Default assumption, immediately queried
    
    /// Callback for lid state changes.
    ///
    /// This closure is called whenever the lid state changes.
    /// - Parameter isOpen: `true` if the lid is open, `false` otherwise.
    public var onLidStateChange: ((Bool) -> Void)?
    
    // Monitoring state
    private var isMonitoring: Bool = false

    /// Initializes a new `LidStateMonitor` instance.
    ///
    /// This initializer queries the initial lid state immediately.
    public init() {
        logger.debug("Initializing LidStateMonitor")
        // Query initial state immediately
        queryAndUpdateLidState()
    }

    deinit {
        logger.debug("Deinitializing LidStateMonitor")
        stopMonitoring()
    }
    
    /// Starts monitoring lid state changes.
    ///
    /// This method sets up the necessary IOKit notifications to detect lid state changes.
    /// - Throws: `LidStateMonitorError` if setup fails.
    public func startMonitoring() throws {
        guard !isMonitoring else { return }
        logger.debug("Starting lid state monitoring")
        try setupPowerNotification()
        isMonitoring = true
    }
    
    /// Stops monitoring lid state changes.
    ///
    /// This method tears down the IOKit notifications and stops monitoring lid state changes.
    public func stopMonitoring() {
        guard isMonitoring else { return }
        logger.debug("Stopping lid state monitoring")
        tearDownPowerNotification()
        isMonitoring = false
    }

    private func setupPowerNotification() throws {
        rootPort = IORegisterForSystemPower(Unmanaged.passUnretained(self).toOpaque(), &notificationPort, powerCallback, &notifier)
        if rootPort == 0 {
            throw LidStateMonitorError.registrationFailed
        }

        guard let notificationPort = notificationPort else {
            throw LidStateMonitorError.notificationPortNil
        }

        // Add the notification port to the run loop
        let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        logger.info("Successfully registered for system power notifications.")
    }

    private func tearDownPowerNotification() {
        if let port = notificationPort {
            let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            IONotificationPortDestroy(port)
            notificationPort = nil
            logger.info("Removed notification port from run loop and destroyed.")
        }

        if notifier != 0 {
             // Deregister notification
            if kIOReturnSuccess != IODeregisterForSystemPower(&notifier) {
                logger.error("IODeregisterForSystemPower failed.")
            }
            IOObjectRelease(notifier)
            notifier = 0
            logger.info("Deregistered and released system power notifier.")
        }

        if rootPort != 0 {
            if kIOReturnSuccess != IOServiceClose(rootPort) {
                logger.error("IOServiceClose failed for root power domain port.")
            }
            rootPort = 0
            logger.info("Closed root power domain port.")
        }
    }
}

// C-style callback function
private func powerCallback(refcon: UnsafeMutableRawPointer?, service: io_service_t, messageType: UInt32, messageArgument: UnsafeMutableRawPointer?) -> Void {
    guard let refcon = refcon else {
        os_log(.error, "Power callback invoked without valid refcon.")
        return
    }
    
    let monitor = Unmanaged<LidStateMonitor>.fromOpaque(refcon).takeUnretainedValue()
    let logger = monitor.logger // Use the instance's logger
    let rootPortRef = monitor.rootPort // Capture for use in allowing/denying sleep
    _ = messageArgument.map { $0.load(as: UInt32.self) } ?? 0

    // Define IOKit message constants since the macros aren't directly accessible
    let kIOMessageSystemWillSleep: UInt32 = 0x280
    let kIOMessageCanSystemSleep: UInt32 = 0x270
    let kIOMessageSystemWillPowerOn: UInt32 = 0x320
    let kIOMessageSystemHasPoweredOn: UInt32 = 0x300
    let kIOMessageSystemWillNotSleep: UInt32 = 0x290

    switch messageType {
    case kIOMessageSystemWillSleep:
        logger.debug("Received kIOMessageSystemWillSleep")
        // System is going to sleep. Assume lid is closed for this event.
        // A more robust approach might query *before* allowing sleep,
        // but Apple docs suggest handling sleep quickly.
        monitor.updateLidState(isOpen: false)
        // Acknowledge receipt of message
        if let messageArg = messageArgument {
            IOAllowPowerChange(rootPortRef, Int(bitPattern: messageArg))
        }

    case kIOMessageCanSystemSleep:
        logger.debug("Received kIOMessageCanSystemSleep - Allowing sleep")
        // Allow sleep
        if let messageArg = messageArgument {
            IOAllowPowerChange(rootPortRef, Int(bitPattern: messageArg))
        }

    case kIOMessageSystemWillPowerOn:
        logger.debug("Received kIOMessageSystemWillPowerOn")
        // System is waking up, but devices might not be ready. Do nothing here.
        // Acknowledge receipt
        if let messageArg = messageArgument {
            IOAllowPowerChange(rootPortRef, Int(bitPattern: messageArg))
        }

    case kIOMessageSystemHasPoweredOn:
        logger.debug("Received kIOMessageSystemHasPoweredOn")
        // System has woken up. Query the actual lid state now.
        monitor.queryAndUpdateLidState()
        // Acknowledge receipt
        if let messageArg = messageArgument {
            IOAllowPowerChange(rootPortRef, Int(bitPattern: messageArg))
        }

    case kIOMessageSystemWillNotSleep:
         logger.debug("Received kIOMessageSystemWillNotSleep")
        // Acknowledge receipt
        if let messageArg = messageArgument {
            IOAllowPowerChange(rootPortRef, Int(bitPattern: messageArg))
        }

    default:
        logger.debug("Received unhandled power message type: \(messageType)")
        // Allow other message types by default
        if let messageArg = messageArgument {
            IOAllowPowerChange(rootPortRef, Int(bitPattern: messageArg))
        }
     }
 }

extension LidStateMonitor {
    /// Updates the internal lid state and notifies the `onLidStateChange` callback if the state changes.
    ///
    /// - Parameter isOpen: `true` if the lid is open, `false` otherwise.
    fileprivate func updateLidState(isOpen: Bool) {
        if self.isLidOpen != isOpen {
            logger.info("Lid state changed to: \(isOpen ? "Open" : "Closed")")
            self.isLidOpen = isOpen
            // Notify delegates or publish changes here later
            onLidStateChange?(isOpen)
        }
    }

    /// Queries the IOKit registry for the current clamshell (lid) state.
    ///
    /// This method updates the internal `isLidOpen` state and notifies the `onLidStateChange` callback if the state changes.
    fileprivate func queryAndUpdateLidState() {
        logger.debug("Querying current lid state...")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))

        var clamshellState = false // Default to closed if query fails

        if service != 0 {
            if let prop = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0) {
                // Ensure the property is a CFBoolean
                if CFGetTypeID(prop.takeUnretainedValue()) == CFBooleanGetTypeID() {
                    let boolValue = prop.takeUnretainedValue() as! CFBoolean
                    clamshellState = CFBooleanGetValue(boolValue)
                    logger.debug("Successfully queried AppleClamshellState: \(clamshellState)")
                } else {
                    logger.warning("AppleClamshellState exists but is not a CFBoolean.")
                }
                // Property was created, takeRetainedValue would balance the create, but we used takeUnretainedValue
                // prop.release() // No longer needed with ARC managing the return? Check CF memory rules.
            } else {
                logger.warning("Failed to get AppleClamshellState property.")
            }
            // Release the service object obtained from IOServiceGetMatchingService
            IOObjectRelease(service)
        } else {
            logger.error("Failed to get IOPlatformExpertDevice service.")
        }

        // Update internal state (Note: AppleClamshellState is TRUE when CLOSED)
        let currentlyOpen = !clamshellState
        updateLidState(isOpen: currentlyOpen)
    }
}
