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

After any set of changes, validate build commands by checking for zero error and warning output. 

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
   - `GlobalShortcutMonitor.swift` - Push-to-talk mode monitoring
   - `PasteService.swift` - Simulates Cmd+V for auto-pasting
   - `SettingsManager.swift` - UserDefaults for non-sensitive preferences
   - `KeychainManager.swift` - Secure API key storage in macOS Keychain
   - `TranscriptionService.swift` - Coordinates recording and transcription
   - `DisplayManager.swift` - Multi-monitor support and overlay positioning
   - `UpdateManager.swift` - Sparkle framework integration for auto-updates
   - `TempFileManager.swift` - Manages temporary audio file cleanup and periodic maintenance

## Key Implementation Details

### Recording Modes
1. **Toggle Mode** (default): Press Option+Space to start/stop
2. **Push-to-Talk Mode**: Hold Option+Space to record, release to stop

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
- Update feed: `https://raw.githubusercontent.com/Rkaede/echo/main/docs/appcast.xml`
- Public key: `hX7VZOZJ7tkQfO3ewTtWrWlcr7fIeGAcUtOfLJzPzuE=`
- Check interval: 7 days (604800 seconds)
- Version info in Info.plist: `CFBundleShortVersionString` and `CFBundleVersion`

## Security & Storage

### Data Storage
- **Keychain**: API keys via `KeychainManager`
- **UserDefaults**: Non-sensitive preferences (selected model, onboarding status)
- **Temporary files**: Audio recordings stored in `/tmp/echo/` and automatically cleaned up
  - Immediate cleanup after transcription success/failure
  - Periodic cleanup every 30 minutes for orphaned files (>1 hour old)
  - Startup cleanup to remove files from previous sessions

### Entitlements
- **Development**: Non-sandboxed for debugging
- **Release**: Sandboxed with:
  - `com.apple.security.audio-input` - Microphone access
  - `com.apple.security.network.client` - API requests
  - `com.apple.security.automation.apple-events` - Accessibility for pasting

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
2. Build release configuration
3. Sign and notarize the app
4. Update `docs/appcast.xml` with new release info
5. Use `scripts/release.sh` for automation