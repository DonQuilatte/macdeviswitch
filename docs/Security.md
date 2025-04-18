# MacDeviSwitch Security Documentation

## Entitlements

MacDeviSwitch requires the following entitlements to function properly:

### 1. Audio Input Access

**Entitlement**: `com.apple.security.device.audio-input`

**Justification**: MacDeviSwitch needs to access and control audio input devices to perform its core functionality of switching between microphones based on lid state and external display connection.

### 2. Hardened Runtime

MacDeviSwitch uses the Hardened Runtime to protect users from malicious code. This provides the following security benefits:

- Code signing enforcement
- Library validation
- Debugging restrictions
- Resource access restrictions
- Runtime protections

## Privacy Considerations

### Data Collection

MacDeviSwitch does not collect any user data beyond what is necessary for its core functionality:

- Audio device information (names, UIDs)
- User preferences (target microphone, revert behavior)

This information is stored locally on the user's device and is not transmitted to any external servers.

### Privacy Usage Descriptions

The following privacy usage descriptions are included in the app's Info.plist:

- **NSMicrophoneUsageDescription**: "MacDeviSwitch needs access to your microphone to detect and switch between audio input devices based on your preferences."

## Least Privilege Principle

MacDeviSwitch follows the principle of least privilege by:

1. Only requesting entitlements that are absolutely necessary for its functionality
2. Only accessing system resources when needed
3. Not requesting network access or other unnecessary permissions

## Security Best Practices

The following security best practices are implemented in MacDeviSwitch:

1. **Input Validation**: All user inputs and system data are validated before use
2. **Error Handling**: Comprehensive error handling to prevent crashes and unexpected behavior
3. **Logging**: Sensitive information is not logged
4. **Memory Management**: Proper memory management to prevent leaks and vulnerabilities

## Third-Party Dependencies

MacDeviSwitch does not use any third-party dependencies, eliminating potential security risks from external code.

## Security Testing

The following security testing is performed on MacDeviSwitch:

1. **Static Analysis**: Using Xcode's built-in static analyzer
2. **Runtime Analysis**: Using Instruments to detect memory leaks and other issues
3. **Manual Testing**: Testing edge cases and potential security issues

## Reporting Security Issues

If you discover a security vulnerability in MacDeviSwitch, please report it by sending an email to security@example.com.
