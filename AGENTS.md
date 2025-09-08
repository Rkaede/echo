# Repository Guidelines

## Project Structure & Module Organization
- App source lives in `echo/`, grouped by feature: `Views/`, `Components/`, `Models/`, `Services/`, and `ViewModels/` drive the SwiftUI UI, state, and data flows.
- Assets and icons are managed in `echo/Assets.xcassets`; shared constants sit in `echo/Constants.swift`.
- The macOS project file is `Echo.xcodeproj`; `DerivedData/`, `build/`, and `exports/` contain local build outputs that should not be committed.
- Reference docs, changelogs, and planning notes are in `docs/`, `CHANGELOG.md`, and `plan.md`.

## Build, Test, and Development Commands
- `open Echo.xcodeproj` — launch Xcode with the Echo workspace for interactive development.
- `xcodebuild -project Echo.xcodeproj -scheme Echo -configuration Debug build` — command-line build used by CI or local smoke checks.
- `xcodebuild -project Echo.xcodeproj -scheme Echo test` — run the scheme’s unit/UI tests (add a destination such as `-destination 'platform=macOS'` when needed).
- `scripts/reset-tcc.sh` — clears macOS TCC permissions when microphone or accessibility prompts get wedged.

## Coding Style & Naming Conventions
- Use 2-space indentation, trailing commas where Swift encourages them, and prefer SwiftUI’s modifier-first formatting as demonstrated in `Views/OverlayView.swift`.
- Types are `PascalCase`, methods and variables are `camelCase`, and SwiftUI environment keys stay scoped to the feature.
- Keep files focused; split oversized views into subviews in `Components/`.

## Testing Guidelines
- Add XCTest cases under a new `EchoTests/` target; mirror source folders (e.g., `ViewsTests/OverlayViewTests.swift`).
- Prefer succinct, behavior-driven method names such as `testRecordingOverlayShowsProfileIcon()`.
- Manual QA still matters: run a local build, trigger recordings, and verify overlay, permissions prompts, and paste behavior before merging.

## Commit & Pull Request Guidelines
- Follow the existing Conventional Commit prefixes (`feat:`, `fix:`, `chore:`, `release:`) seen in `git log`.
- Keep commits focused and include context in the body when touching audio, overlay, or profile workflows.
- PRs should describe motivation, list validation steps (`xcodebuild ...`, manual QA notes), attach screenshots for UI changes, and reference related issues or roadmap tasks.

## Security & Configuration Tips
- Never commit API keys; use the macOS Keychain integration in `SettingsManager`.
- Temporary audio lives in `/tmp/echo/`; confirm cleanup when modifying recorder or post-processing paths.
- Review permission-related changes with `scripts/reset-tcc.sh` to ensure onboarding remains smooth.
