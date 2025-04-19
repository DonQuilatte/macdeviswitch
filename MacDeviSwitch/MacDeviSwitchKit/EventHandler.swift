import Foundation
import os.log

/// Handles system events (lid state, display connection) and triggers an action.
public class SwitchControllerEventHandler: EventHandling {
    private let logger = Logger(subsystem: "via.MacDeviSwitch.kit", category: "SwitchControllerEventHandler")
    private var eventCallback: (() -> Void)?
    private var lidMonitor: LidStateMonitoring?
    private var displayMonitor: DisplayMonitoring?

    public init() {}

    public func startHandlingEvents(
        lidMonitor: LidStateMonitoring,
        displayMonitor: DisplayMonitoring,
        onEvent: @escaping () -> Void
    ) {
        logger.debug("Starting event handling setup.")
        self.eventCallback = onEvent
        self.lidMonitor = lidMonitor
        self.displayMonitor = displayMonitor

        // Set up lid state change handler
        self.lidMonitor?.onLidStateChange = { [weak self] isOpen in
            self?.logger.info("Lid state changed: \(isOpen ? "Open" : "Closed")")
            self?.eventCallback?()
        }

        // Set up display connection change handler
        self.displayMonitor?.onDisplayConnectionChange = { [weak self] isConnected in
            self?.logger.info("Display connection changed: \(isConnected ? "Connected" : "Disconnected")")
            self?.eventCallback?()
        }
        logger.debug("Event handlers configured for lid and display monitors.")
    }

    public func stopHandlingEvents(
        lidMonitor: LidStateMonitoring, // Parameter from caller
        displayMonitor: DisplayMonitoring // Parameter from caller
    ) {
        logger.debug("Stopping event handling.")

        // Call stop on the actual monitors passed in
        lidMonitor.stopMonitoring()
        displayMonitor.stopMonitoring()

        // Clear callbacks on the internally stored references
        self.lidMonitor?.onLidStateChange = nil
        self.displayMonitor?.onDisplayConnectionChange = nil

        // Clear internal references
        self.eventCallback = nil
        self.lidMonitor = nil
        self.displayMonitor = nil
    }
}
