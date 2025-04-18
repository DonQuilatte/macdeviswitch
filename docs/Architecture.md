# MacDeviSwitch Architecture

## Component Overview

MacDeviSwitch follows a modular architecture with clear separation of concerns:

```
┌─────────────────────────────────────────────────────────────┐
│                        MacDeviSwitch                         │
│                                                             │
│  ┌─────────────────┐          ┌───────────────────────┐    │
│  │ AppDelegate     │◄────────►│ StatusBarController   │    │
│  └─────────────────┘          └───────────────────────┘    │
│          │                              │                   │
│          ▼                              ▼                   │
│  ┌─────────────────┐          ┌───────────────────────┐    │
│  │ NotificationMgr │          │ PreferenceManager     │    │
│  └─────────────────┘          └───────────────────────┘    │
│                                         │                   │
└─────────────────────────────────────────┼───────────────────┘
                                          │
┌─────────────────────────────────────────┼───────────────────┐
│                     MacDeviSwitchKit     │                   │
│                                         │                   │
│                                         ▼                   │
│  ┌─────────────────┐          ┌───────────────────────┐    │
│  │ LidStateMonitor │          │ SwitchController      │    │
│  └─────────────────┘          └───────────────────────┘    │
│          ▲                              │                   │
│          │                              │                   │
│          │                              ▼                   │
│  ┌─────────────────┐          ┌───────────────────────┐    │
│  │ DisplayMonitor  │◄─────────┤ AudioDeviceMonitor    │    │
│  └─────────────────┘          └───────────────────────┘    │
│                                         │                   │
│                                         │                   │
│                                         ▼                   │
│                               ┌───────────────────────┐    │
│                               │ AudioSwitcher         │    │
│                               └───────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Data Flow

1. **Event Detection**:
   - `LidStateMonitor` detects lid open/close events
   - `DisplayMonitor` detects display connection/disconnection
   - `AudioDeviceMonitor` tracks available audio devices

2. **Decision Logic**:
   - `SwitchController` evaluates the current state
   - Consults `PreferenceManager` for user preferences

3. **Action**:
   - `AudioSwitcher` changes the system's default audio input
   - `NotificationManager` provides user feedback
   - `StatusBarController` updates the UI

## Dependencies

- **CoreAudio**: For audio device management
- **IOKit**: For lid state detection
- **UserNotifications**: For user feedback

## Component Responsibilities

### MacDeviSwitch (App Target)

- **AppDelegate**: Application lifecycle management and component initialization
- **StatusBarController**: Menu bar UI and user interaction
- **NotificationManager**: User notifications for audio device switching events

### MacDeviSwitchKit (Framework Target)

- **LidStateMonitor**: Detects when the MacBook lid is opened or closed
- **DisplayMonitor**: Detects when external displays are connected or disconnected
- **AudioDeviceMonitor**: Tracks available audio input devices
- **AudioSwitcher**: Handles changing the system's default audio input device
- **PreferenceManager**: Manages user preferences (target microphone, revert behavior)
- **SwitchController**: Orchestrates the switching logic based on system state

## Design Patterns

1. **Dependency Injection**: All components receive their dependencies through initializers, making them testable
2. **Observer Pattern**: Components communicate through callbacks and notifications
3. **Protocol-Oriented Design**: Components implement protocols for better testability and modularity

## Testing Strategy

- **Unit Tests**: Test individual components in isolation using mock implementations
- **Integration Tests**: Test interactions between components
- **Edge Case Tests**: Test failure scenarios and edge cases

## Recent Improvements

- Standardized bundle IDs (now `via.MacDeviSwitch` and `via.MacDeviSwitch.kit`)
- Enhanced error handling using custom error types and Swift's Result type
- Improved memory management and resource cleanup
- Protocol definitions and property names standardized (e.g., `revertToFallbackOnLidOpen`)
- Notification handling now includes permission checks and robust error handling

## Documentation & Testing

- DocC documentation is generated automatically on push to main
- Test coverage ≥ 80% (unit, integration, edge cases)
- All dependencies managed via SwiftPM and pinned in `Package.resolved`
