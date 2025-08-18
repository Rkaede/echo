# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Echo is a macOS menu bar application that provides speech-to-text transcription with automatic pasting. Users press Option+Space to record, and transcribed text is automatically pasted into the active application.

**Key Technologies:**
- Swift 5.0 with SwiftUI
- macOS 15.0+ native application
- MVVM architecture pattern
- Combine framework for reactive programming
- AVFoundation for audio recording
- Groq API (Whisper model) for speech-to-text
- Sparkle framework for automatic updates

## Build Commands

```bash
# Build the app
xcodebuild -scheme Echo -configuration Debug build

# Build for release
xcodebuild -scheme Echo -configuration Release build

# Run tests
xcodebuild -scheme Echo test

# Clean build
xcodebuild -scheme Echo clean

# Build and run in Xcode (preferred for development)
open Echo.xcodeproj
```

## Build Validation

After any set of changes, validate builds:

```bash
# Validate Debug build
xcodebuild -scheme Echo -configuration Debug build | grep -E "(error|warning)"

# Validate Release build
xcodebuild -scheme Echo -configuration Release build | grep -E "(error|warning)"

# Run all tests
xcodebuild -scheme Echo test

# Check for zero errors and warnings in output
``` 

## Testing

Tests are configured using Swift Testing framework (Apple's new testing framework) but not yet implemented. Test targets exist:
- `EchoTests` - Unit tests
- `EchoUITests` - UI tests

Run tests with Cmd+U in Xcode or `xcodebuild -scheme Echo test`.

## Architecture

The codebase follows MVVM pattern with clear separation:

1. **Models/** - Core business logic and data structures
   - `AppState.swift` - Central state management with recording states:
     - `idle` - Ready to record
     - `initiatingRecording` - Requesting microphone permission
     - `recording` - Actively recording audio
     - `processing` - Sending to Groq API
     - `inserted` - Text pasted successfully
     - `error` - Error occurred with message
   - `AudioRecorder.swift` - AVAudioRecorder wrapper for 16kHz mono WAV capture
   - `TranscriptionResult.swift` - Groq API response models

2. **ViewModels/** - Orchestration and business logic
   - `TranscriptionViewModel.swift` - Main workflow controller that coordinates recording, API calls, and pasting

3. **Views/** - SwiftUI interfaces
   - `OverlayView.swift` - Floating status window (300x60 with padding for animations)
   - `SettingsView.swift` - API key configuration and update preferences
   - `OnboardingView.swift` - First-time setup flow for permissions and API key

4. **Services/** - External integrations and utilities
   - `GroqClient.swift` - Groq API transcription requests
   - `HotkeyManager.swift` - Global hotkey (Option+Space) for toggle mode
   - `GlobalShortcutMonitor.swift` - Push-to-talk mode monitoring (Fn key)
   - `PasteService.swift` - Simulates Cmd+V for auto-pasting
   - `SettingsManager.swift` - UserDefaults for non-sensitive preferences
   - `KeychainManager.swift` - Secure API key storage in macOS Keychain
   - `TranscriptionService.swift` - Coordinates recording and transcription
   - `DisplayManager.swift` - Multi-monitor support and overlay positioning
   - `UpdateManager.swift` - Sparkle framework integration for auto-updates
   - `TempFileManager.swift` - Manages temporary audio file cleanup and periodic maintenance
   - `PermissionService.swift` - Handles microphone and accessibility permissions
   - `AccessibilityService.swift` - Manages accessibility permissions and events
   - `AppStateService.swift` - Central state management service
   - `NotificationService.swift` - System notifications and user feedback

5. **Components/** - Reusable UI components
   - `PermissionStatusView.swift` - Permission status indicators
   - `ModelSelectionView.swift` - Groq model selection interface
   - `VolumeVisualizerView.swift` - Audio level visualization
   - `StatusIndicatorView.swift` - Recording status indicators

## Key Implementation Details

### Recording Modes
1. **Toggle Mode** (default): Press Option+Space to start/stop
2. **Push-to-Talk Mode**: Hold Fn key to record, release to stop

### Recording Workflow
Managed by `TranscriptionService` and `TranscriptionViewModel`:
1. User triggers recording → Check API key and permissions
2. Start recording → `AudioRecorder` captures to temporary WAV file
3. Stop recording → Upload audio to Groq API
4. Process response → Extract transcribed text
5. Auto-paste → `PasteService` simulates Cmd+V
6. Cleanup → Delete temporary audio file

### Window Management
Overlay window configuration in `App.swift`:
- Floats above all windows (`NSWindow.Level.mainMenuWindow`)
- Visible on all spaces (`canJoinAllSpaces`)
- Borderless with transparent background
- 300x60 size with 20px horizontal padding for animations
- Automatically repositions to active monitor

### API Integration
**Groq API Configuration:**
- Endpoint: `https://api.groq.com/openai/v1/audio/transcriptions`
- Audio format: 16kHz, 16-bit, mono WAV
- Default model: `whisper-large-v3` (configurable in settings)
- Request format: Multipart form data
- Response format: `verbose_json` with timestamps

### Automatic Updates
**Sparkle Configuration:**
- Update feed: `https://raw.githubusercontent.com/corey-taylor/echo/main/docs/appcast.xml`
- Public key: `hX7VZOZJ7tkQfO3ewTtWrWlcr7fIeGAcUtOfLJzPzuE=`
- Check interval: 7 days (604800 seconds)
- Version info in Info.plist: `CFBundleShortVersionString` and `CFBundleVersion`
- Automated via `scripts/release.sh` with appcast generation

## Security & Storage

### Data Storage
- **Keychain**: API keys via `KeychainManager`
- **UserDefaults**: Non-sensitive preferences (selected model, onboarding status)
- **Temporary files**: Audio recordings managed by `TempFileManager`
  - Storage location: `/tmp/echo/` directory
  - Immediate cleanup after transcription success/failure
  - Periodic maintenance every 30 minutes removes files >1 hour old
  - Startup cleanup removes orphaned files from previous app sessions
  - Automatic directory creation and permission handling

### Entitlements
- **Development** (`Echo.entitlements`): Non-sandboxed for debugging
  - `com.apple.security.audio-input` - Microphone access
  - `com.apple.security.network.client` - API requests
  - `com.apple.security.automation.apple-events` - Accessibility for pasting
- **Release** (`EchoRelease.entitlements`): Sandboxed with:
  - `com.apple.security.app-sandbox` - App Store sandbox
  - `com.apple.security.audio-input` - Microphone access
  - `com.apple.security.network.client` - API requests
  - `com.apple.security.automation.apple-events` - Accessibility for pasting
  - `com.apple.security.files.user-selected.read-write` - File access when needed

### Required Permissions
1. **Microphone**: Audio recording (requested on first use)
2. **Accessibility**: Keyboard event simulation for auto-paste

## Dependencies

### Swift Package Manager
- **HotKey** (0.2.1): Global hotkey registration
- **Sparkle**: Automatic update framework

Package resolution stored in `Package.resolved`.

## Common Development Tasks

### To modify the hotkey:
1. Edit `HotkeyManager.swift` - Change `Key.space` and/or `NSEvent.ModifierFlags.option`
2. Update `GlobalShortcutMonitor.swift` for push-to-talk mode

### To change API provider:
1. Replace `GroqClient.swift` implementation
2. Update `TranscriptionResult.swift` models
3. Modify `TranscriptionService` if workflow changes

### To adjust overlay window:
1. Edit size constants in `App.swift` (currently 300x60)
2. Update `OverlayView.swift` for UI changes
3. Modify `DisplayManager.swift` for positioning logic

### To release a new version:
1. Update version in `Info.plist` (`CFBundleShortVersionString` and `CFBundleVersion`)
2. Run automated release script: `./scripts/release.sh`
   - Builds release configuration
   - Signs and notarizes the app
   - Creates DMG installer
   - Generates and updates `docs/appcast.xml`
   - Uploads artifacts to GitHub releases

### Release Automation
The `scripts/release.sh` script automates the complete release workflow:
- Version validation and Git tagging
- Xcode build with proper code signing
- macOS notarization process
- DMG creation and signing
- Sparkle appcast XML generation
- GitHub release creation with artifacts