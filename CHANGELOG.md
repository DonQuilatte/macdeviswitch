# Changelog

## [Unreleased]
### Added
- Standardized all bundle IDs to `via.MacDeviSwitch` and `via.MacDeviSwitch.kit`
- Enhanced error handling: custom error types, LocalizedError, Result type APIs
- Memory management improvements: resource cleanup, weak self in closures
- Protocol/property naming consistency (e.g., `revertToFallbackOnLidOpen`)
- Notification permission checks and robust error handling
- DocC documentation and test coverage enforcement (≥80%)
- Security documentation and privacy clarifications

### Fixed
- Removed duplicate protocol definitions and circular dependencies
- Fixed unused variable warnings and logger formatting
- Addressed potential retain cycles and resource leaks

### Changed
- Modularized architecture with protocol-based dependency injection
- Observer and facade patterns for event handling and CoreAudio
- Updated onboarding instructions and build/test scripts

---

See `/Docs` for architecture, security, and privacy details.
