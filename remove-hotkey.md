# Plan: Remove HotKey Dependency

## Overview

Replace the external HotKey library with native macOS APIs by extending the existing `GlobalShortcutMonitor.swift` service. This will consolidate keyboard monitoring into a single service and reduce external dependencies.

## Current State Analysis

### HotKey Usage
- `HotkeyManager.swift` uses HotKey library for Option+Space toggle recording
- `GlobalShortcutMonitor.swift` already handles system-wide keyboard monitoring using CGEvent taps
- Both services are instantiated in `App.swift` and work independently

### GlobalShortcutMonitor Capabilities
- Already monitors Fn key (push-to-talk), Escape (cancel), Arrow keys (profile switching)
- Uses CGEvent taps with proper event masking and callback handling
- Has infrastructure for published properties and state management

## Implementation Plan

### Step 1: Extend GlobalShortcutMonitor.swift
- Add `@Published var shouldToggleRecording = false` property
- Modify `handleKeyDown` method to detect Option+Space combination:
  - Check for keycode 49 (Space key)
  - Verify Option modifier flag is pressed
  - Toggle the new published property
- Add suspend/resume functionality for the toggle hotkey similar to recording state

### Step 2: Remove HotkeyManager.swift
- Delete `echo/Services/HotkeyManager.swift` file entirely
- Its functionality will be merged into GlobalShortcutMonitor

### Step 3: Update App.swift
- Remove `import HotKey` statement
- Remove `@StateObject private var hotkeyManager = HotkeyManager.shared` line
- Keep only `globalShortcutMonitor` for all keyboard monitoring

### Step 4: Update ShortcutRecorderView.swift
- Replace all `HotkeyManager.shared` references with `GlobalShortcutMonitor.shared`
- Update method calls:
  - `suspendToggleHotkey()` → `suspendToggleHotkey()` (new method in GlobalShortcutMonitor)
  - `resumeToggleHotkey()` → `resumeToggleHotkey()` (new method in GlobalShortcutMonitor)

### Step 5: Update TranscriptionViewModel.swift
- Change subscription from `hotkeyManager.shouldTriggerRecording` to `globalShortcutMonitor.shouldToggleRecording`
- Update any related state management logic

### Step 6: Remove Package Dependency
- Remove HotKey from Xcode project's Swift Package Manager dependencies
- This will automatically clean up Package.resolved

### Step 7: Update Documentation
- Update `CLAUDE.md` to reflect the consolidated keyboard monitoring approach
- Remove references to HotKey dependency
- Update architecture documentation

## Technical Details

### Option+Space Detection Implementation
```swift
private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    
    switch keyCode {
    case 49: // Space key
        if flags.contains(.maskAlternate) {
            // Option+Space detected
            DispatchQueue.main.async {
                self.shouldToggleRecording.toggle()
            }
        }
    // ... existing cases
    }
}
```

### Suspend/Resume Functionality
- Track toggle hotkey state with private boolean
- Modify event handling to respect suspended state
- Provide public methods matching HotkeyManager API

## Benefits

1. **Reduced Dependencies**: Eliminates external HotKey library dependency
2. **Code Consolidation**: Single service for all keyboard monitoring
3. **Consistency**: All keyboard events handled through same CGEvent infrastructure
4. **Maintainability**: Less complex dependency management
5. **Performance**: Potentially better performance with unified event handling

## Risks & Considerations

1. **Event Priority**: Ensure Option+Space doesn't conflict with existing monitoring
2. **Modifier Handling**: Verify Option key detection works consistently across different keyboard layouts
3. **Backward Compatibility**: Ensure all existing hotkey functionality remains intact
4. **Testing**: Thoroughly test all keyboard shortcuts after consolidation

## Testing Strategy

1. Verify Option+Space toggle recording works
2. Confirm Fn key push-to-talk still functions
3. Test Escape key cancellation
4. Verify arrow key profile switching
5. Test suspend/resume functionality in shortcut recorder
6. Confirm no conflicts between different keyboard shortcuts