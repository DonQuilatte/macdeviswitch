# MacDeviSwitch

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)]()
[![Swift](https://img.shields.io/badge/swift-5.9-blue)]()
[![Xcode](https://img.shields.io/badge/xcode-15.4-blue)]()
[![Coverage](https://img.shields.io/badge/coverage-80%25-green)]()

## Description

**MacDeviSwitch** is a macOS menu bar application that automatically switches your audio input device based on your MacBook’s lid state and external display connections. It is designed for seamless transitions between internal and external microphones, with robust error handling, privacy, and security.

## Features

- Auto-switch to external mic when lid is closed and external display is connected
- Optional revert to internal mic when lid is opened
- Manual device selection via menu bar
- Visual and notification-based feedback
- Persistent user preferences
- Secure, privacy-focused, and App Store-ready

## Architecture

- Modular MVVM architecture with Coordinator pattern
- Protocol-based dependency injection for testability
- Observer pattern for event handling
- Facade pattern for CoreAudio APIs

See [Docs/Architecture.md](Docs/Architecture.md) for a full diagram and component overview.

## Building

```sh
brew bundle && windsurf setup
open MacDeviSwitch.xcodeproj
```
- All code passes `SwiftLint --strict` and `clang-format`
- Test coverage ≥ 80% (`swift test --parallel`)
- Security: `xcodebuild analyze` + MobSF scan

## Documentation

- DocC generated automatically on push to main
- See `/Docs` for architecture, security, and privacy

## Contributing

- See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines
- All PRs require green CI, docs, and test coverage

## License

MIT
