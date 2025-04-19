import Foundation
import os.log

/// Protocol defining the requirements for handling system events relevant to audio switching.
protocol EventHandling {
    /// Starts handling events from the provided monitors.
    ///
    /// - Parameters:
    ///   - lidMonitor: The monitor for lid state changes.
    ///   - displayMonitor: The monitor for display connection changes.
    ///   - onEvent: A closure to be called when a relevant event occurs.
    func startHandlingEvents(
        lidMonitor: LidStateMonitoring,
        displayMonitor: DisplayMonitoring,
        onEvent: @escaping () -> Void
    )

    /// Stops handling events.
    func stopHandlingEvents(
        lidMonitor: LidStateMonitoring,
        displayMonitor: DisplayMonitoring
    )
}

/// Handles system events (lid state, display connection) and triggers an action.
class SwitchControllerEventHandler: EventHandling {
    private let logger = Logger(subsystem: "via.MacDeviSwitch.kit", category: "SwitchControllerEventHandler")
    private var eventCallback: (() -> Void)?

    func startHandlingEvents(
        lidMonitor: LidStateMonitoring,
        displayMonitor: DisplayMonitoring,
        onEvent: @escaping () -> Void
    ) {
        logger.debug("Starting event handling setup.")
        self.eventCallback = onEvent

        // Set up lid state change handler
        lidMonitor.onLidStateChange = { [weak self] isOpen in
            self?.logger.info("Lid state changed: \(isOpen ? "Open" : "Closed")")
            self?.eventCallback?()
        }

        // Set up display connection change handler
        displayMonitor.onDisplayConnectionChange = { [weak self] isConnected in
            self?.logger.info("Display connection changed: \(isConnected ? "Connected" : "Disconnected")")
            self?.eventCallback?()
        }
        logger.debug("Event handlers configured for lid and display monitors.")
    }

    func stopHandlingEvents(
        lidMonitor: LidStateMonitoring,
        displayMonitor: DisplayMonitoring
    ) {
        logger.debug("Stopping event handling.")
        lidMonitor.onLidStateChange = nil
        displayMonitor.onDisplayConnectionChange = nil
        self.eventCallback = nil
    }
}
