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
- SQLite for transcription history storage

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

The project uses **Swift Testing framework** (Apple's modern testing framework introduced in Swift 5.9+). Tests are implemented for core logic and state management.

### Test Structure

**Test Targets:**
- `EchoTests` - Unit tests for business logic and state management
- `EchoUITests` - UI tests (not yet implemented)

**Current Test Coverage:**
- `UnifiedAudioEngineTests.swift` - Comprehensive tests for the audio engine
  - Error enum descriptions and LocalizedError conformance
  - Sound type enum validation
  - State management (singleton, recording state, invalid inputs)
  - Buffer calculation logic (frame capacity, safety margins)
  - File cleanup operations
  - Thread safety validation (basic concurrent access)
  - Audio format validation (16kHz mono PCM)
  - Level monitoring calculations (RMS to dB conversion, normalization)

**Setup Instructions:**
See `EchoTests/README.md` for detailed setup instructions for adding the test target to Xcode.

### Running Tests

**Command Line:**
```bash
# Run all tests
xcodebuild -scheme Echo test

# Run with code coverage
xcodebuild -scheme Echo test -enableCodeCoverage YES

# Run specific test suite
xcodebuild -scheme Echo test -only-testing:EchoTests/UnifiedAudioEngineTests
```

**Xcode:**
- Press `Cmd + U` to run all tests
- Click the diamond icon next to individual tests to run them
- View results in Test Navigator (`Cmd + 6`)

### Testing Limitations

The current tests focus on **testable logic without hardware dependencies**:

✅ **What IS Tested:**
- Pure logic (calculations, state management, error handling)
- Public API behavior (error cases, state validation)
- Thread safety at a basic level

❌ **What is NOT Tested** (requires hardware/mocking):
- Actual audio recording/playback with AVAudioEngine
- Microphone permission flows
- Audio tap callbacks (run on separate threads)
- Real-time format conversion
- Bluetooth device switching
- Live audio level monitoring accuracy

### Future Testing Improvements

To test hardware-dependent features, the codebase would need:
1. **Protocol-based dependency injection** for AVAudioEngine
2. **Mock implementations** of audio components
3. **Integration test environment** with microphone permissions
4. **UI tests** for end-to-end recording workflows

### Adding New Tests

Follow the Swift Testing framework conventions:

```swift
import Testing
@testable import Echo

@MainActor
@Suite("My Test Suite")
struct MyTests {
  @Test("Description of what this tests")
  func myTest() async throws {
    #expect(actualValue == expectedValue)
  }
}
```

Run tests with Cmd+U in Xcode or `xcodebuild -scheme Echo test`.

## Architecture

The codebase follows MVVM pattern with clear separation:

1. **Models/** - Core business logic and data structures
   - `AppState.swift` - Central state management with recording states:
     - `idle` - Ready to record
     - `initiatingRecording` - Requesting microphone permission
     - `recording` - Actively recording audio
     - `processing` - Sending to Groq API
     - `postProcessing` - Running LLM post-processing on transcribed text
     - `inserted` - Text pasted successfully
     - `cancelled` - Recording cancelled by user
     - `confirmingCancel` - Showing cancellation confirmation dialog
     - `error` - Error occurred with message
   - `AudioRecorder.swift` - AVAudioRecorder wrapper for 16kHz mono WAV capture
   - `TranscriptionResult.swift` - Groq API response models
   - `Profile.swift` - User profile system for different recording configurations
   - `TranscriptionHistory.swift` - SQLite-backed history storage models
   - `ChatCompletionModels.swift` - LLM post-processing API models

2. **ViewModels/** - Orchestration and business logic
   - `TranscriptionViewModel.swift` - Main workflow controller that coordinates recording, API calls, and pasting

3. **Views/** - SwiftUI interfaces
   - `OverlayView.swift` - Floating status window (300x60 with padding for animations)
   - `SettingsView.swift` - Main settings interface with tabs for API, profiles, and preferences
   - `ProfilesSettingsView.swift` - Profile management interface
   - `OnboardingView.swift` - First-time setup flow for permissions and API key
   - `HistoryView.swift` - Transcription history browser with search and audio playback

4. **Services/** - External integrations and utilities
   - `GroqClient.swift` - Groq API transcription requests
   - `GlobalShortcutMonitor.swift` - Push-to-talk mode monitoring (Fn key)
   - `PasteService.swift` - Simulates Cmd+V for auto-pasting
   - `SettingsManager.swift` - UserDefaults for non-sensitive preferences
   - `KeychainManager.swift` - Secure API key storage in macOS Keychain
   - `TranscriptionService.swift` - Coordinates recording and transcription
   - `UnifiedAudioEngine.swift` - Production-ready audio engine with thread-safe recording/playback (fully tested)
   - `DisplayManager.swift` - Multi-monitor support and overlay positioning
   - `UpdateManager.swift` - Sparkle framework integration for auto-updates
   - `TempFileManager.swift` - Manages temporary audio file cleanup and periodic maintenance
   - `PermissionManager.swift` - Handles microphone and accessibility permissions
   - `LaunchAtLogin.swift` - macOS launch at login functionality
   - `DatabaseService.swift` - SQLite database management for history
   - `HistoryManager.swift` - Transcription history operations and queries
   - `ProfilesService.swift` - Profile management and switching
   - `ProfilesRepository.swift` - Profile data persistence
   - `DefaultProfilesProvider.swift` - Built-in profile templates
   - `PostProcessing.swift` - LLM post-processing pipeline
   - `SoundManager.swift` - Audio feedback and notification sounds
   - `AudioStorageManager.swift` - Audio file storage for history playback
   - `AudioPlayerManager.swift` - Audio playback controls for history

5. **Components/** - Reusable UI components
   - `PermissionStatusView.swift` - Permission status indicators
   - `AudioControlsView.swift` - Audio playback controls for history
   - `ColorPickerView.swift` - Profile color selection interface
   - `IconPickerView.swift` - Profile icon selection interface
   - `OverlayWaveformView.swift` - Real-time audio waveform visualization
   - `ProfileAppearancePalette.swift` - Profile visual customization
   - `ProfileListIconView.swift` - Profile icons in lists
   - `SettingsButton.swift` - Reusable settings button component
   - `ShortcutRecorderView.swift` - Hotkey recording interface

## Key Implementation Details

### Recording Modes
1. **Toggle Mode** (default): Press Option+Space to start/stop
2. **Push-to-Talk Mode**: Hold Fn key to record, release to stop

### Profile System
Echo supports multiple user profiles with customizable settings:
- **Profile Configuration**: Different hotkeys, models, post-processing settings per profile
- **Visual Customization**: Custom icons and colors for each profile
- **Default Profiles**: Built-in templates for common use cases
- **Profile Switching**: Quick switching via settings or overlay display

### Recording Workflow
Managed by `TranscriptionService` and `TranscriptionViewModel`:
1. User triggers recording → Check API key and permissions
2. Start recording → `AudioRecorder` captures to temporary WAV file
3. Stop recording → Upload audio to Groq API
4. Process response → Extract transcribed text
5. **Optional Post-Processing** → Run through LLM for enhancement/correction
6. **History Storage** → Save transcription and audio to SQLite database
7. Auto-paste → `PasteService` simulates Cmd+V
8. Cleanup → Delete temporary audio file (but preserve history audio)

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
- Update feed: `https://rkaede.github.io/echo/appcast.xml`
- Public key: `hX7VZOZJ7tkQfO3ewTtWrWlcr7fIeGAcUtOfLJzPzuE=`
- Check interval: 7 days (604800 seconds)
- Version info in Info.plist: `CFBundleShortVersionString` and `CFBundleVersion`
- Automated via `scripts/release.sh` with appcast generation

## Security & Storage

### Data Storage
- **Keychain**: API keys via `KeychainManager`
- **UserDefaults**: Non-sensitive preferences (selected model, onboarding status, profile settings)
- **SQLite Database**: Transcription history via `DatabaseService` and `HistoryManager`
  - Storage location: Application Support directory
  - Full-text search capabilities
  - Audio file references for playback
- **Temporary files**: Audio recordings managed by `TempFileManager`
  - Storage location: `/tmp/echo/` directory
  - Immediate cleanup after transcription success/failure
  - Periodic maintenance every 30 minutes removes files >1 hour old
  - Startup cleanup removes orphaned files from previous app sessions
  - Automatic directory creation and permission handling
- **History Audio**: Long-term audio storage via `AudioStorageManager`
  - Organized by date for easy cleanup and management
  - Referenced by database for playback functionality

### Entitlements
- **Development** (`echo.entitlements`): Sandboxed for development with debugging enabled
  - `com.apple.security.app-sandbox` - App sandbox enabled
  - `com.apple.security.device.microphone` - Microphone access
  - `com.apple.security.device.audio-input` - Legacy audio input (backward compatibility)
  - `com.apple.security.network.client` - API requests
  - `com.apple.security.accessibility` - Accessibility for pasting
  - `com.apple.security.get-task-allow` - Debugging enabled
  - Sparkle framework mach lookup exceptions for updates
- **Release** (`echoRelease.entitlements`): Production sandbox configuration
  - `com.apple.security.app-sandbox` - App Store sandbox
  - `com.apple.security.device.microphone` - Microphone access
  - `com.apple.security.device.audio-input` - Legacy audio input (backward compatibility)
  - `com.apple.security.network.client` - API requests
  - `com.apple.security.accessibility` - Accessibility for pasting
  - `com.apple.security.get-task-allow` - Debugging disabled for release
  - Sparkle framework mach lookup exceptions for updates

### Required Permissions
1. **Microphone**: Audio recording (requested on first use)
2. **Accessibility**: Keyboard event simulation for auto-paste

## Dependencies

### Swift Package Manager
- **Sparkle**: Automatic update framework

Package resolution stored in `Package.resolved`.

## Common Development Tasks

### To modify the hotkey:
1. Edit `HotkeyManager.swift` - Change `Key.space` and/or `NSEvent.ModifierFlags.option`
2. Update `GlobalShortcutMonitor.swift` for push-to-talk mode
3. Consider profile-specific hotkeys in `Profile.swift` model

### To add a new profile:
1. Update `DefaultProfilesProvider.swift` to add built-in profiles
2. Modify `ProfilesService.swift` for profile management logic
3. Update `ProfilesSettingsView.swift` for UI changes
4. Consider database schema changes in `DatabaseService.swift`

### To add LLM post-processing features:
1. Update `PostProcessing.swift` service for new processing logic
2. Modify `ChatCompletionModels.swift` for new API models
3. Update profile configuration in `Profile.swift` for new settings
4. Add UI controls in `ProfilesSettingsView.swift`

### To change API provider:
1. Replace `GroqClient.swift` implementation
2. Update `TranscriptionResult.swift` models
3. Modify `TranscriptionService` if workflow changes
4. Update post-processing service if using same provider

### To adjust overlay window:
1. For OverlayView: Edit size constants in `App.swift` (currently 300x60)
2. For OverlayViewV2: Update `OverlayViewV2.swift` for new design changes
3. Modify `DisplayManager.swift` for positioning logic
4. Update profile display logic if needed

### To add history features:
1. Update `DatabaseService.swift` for schema changes
2. Modify `HistoryManager.swift` for new query operations
3. Update `HistoryView.swift` for UI enhancements
4. Consider `AudioStorageManager.swift` for audio-related features

### To add tests:
1. Create test file in `EchoTests/` directory (e.g., `MyServiceTests.swift`)
2. Use Swift Testing framework with `@Test` and `#expect()`
3. Mark test classes/structs with `@Suite("Test Suite Name")`
4. Use `@MainActor` for tests that need main actor isolation
5. Import module with `@testable import Echo`
6. Add test file to EchoTests target in Xcode
7. Run tests with `Cmd+U` or `xcodebuild -scheme Echo test`

See `EchoTests/UnifiedAudioEngineTests.swift` for a comprehensive example.

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

