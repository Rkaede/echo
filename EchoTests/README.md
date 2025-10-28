# EchoTests - Unit Test Suite

## Setup Instructions

The test file `UnifiedAudioEngineTests.swift` has been created, but you need to add the test target to Xcode manually.

### Adding the Test Target to Xcode

1. **Open the project in Xcode:**
   ```bash
   open Echo.xcodeproj
   ```

2. **Add Unit Test Target:**
   - Click on the Echo project in the Project Navigator
   - Click the `+` button at the bottom of the targets list
   - Select `Unit Testing Bundle` template
   - Name it: `EchoTests`
   - Product Name: `EchoTests`
   - Team: (your development team)
   - Target to be tested: `Echo`
   - Click `Finish`

3. **Delete the default test file:**
   - Xcode will create a default `EchoTests.swift` file
   - Delete this file (select it and press Delete)
   - Choose "Move to Trash" when prompted

4. **Add the existing test file:**
   - Right-click on the `EchoTests` folder in Project Navigator
   - Select "Add Files to 'Echo'"
   - Navigate to `/Users/corey/dev/SIDE_PROJECTS/AI/echo/EchoTests/`
   - Select `UnifiedAudioEngineTests.swift`
   - Ensure "Add to targets: EchoTests" is checked
   - Click "Add"

5. **Configure test target settings:**
   - Select the `EchoTests` target
   - Go to Build Settings
   - Search for "Swift Language Version" and ensure it's set to Swift 5
   - Go to Build Phases → Link Binary With Libraries
   - Ensure `AVFoundation.framework` is included

6. **Enable Testing in Scheme:**
   - Click on the scheme selector (next to the stop button)
   - Select "Edit Scheme..."
   - Click on "Test" in the left sidebar
   - Click the `+` button
   - Add `EchoTests`
   - Click "Close"

### Running Tests

**Command Line:**
```bash
# Run all tests
xcodebuild -scheme Echo test

# Run specific test
xcodebuild -scheme Echo test -only-testing:EchoTests/UnifiedAudioEngineTests
```

**Xcode:**
- Press `Cmd + U` to run all tests
- Click the diamond next to a test function to run individual tests
- View test results in the Test Navigator (Cmd + 6)

### Test Coverage

The current test suite covers:

✅ **Error Enum Tests**
- Error descriptions
- LocalizedError conformance

✅ **Sound Type Tests**
- Raw values
- Enum exhaustiveness

✅ **State Management Tests**
- Singleton pattern
- Initial state validation
- Invalid URL handling

✅ **Buffer Calculation Tests**
- Frame capacity calculations
- Safety margin validation
- Sample rate conversions

✅ **File Cleanup Tests**
- Temporary file management

✅ **Thread Safety Tests**
- Concurrent access validation

✅ **Format Validation Tests**
- Audio format correctness
- File settings validation

✅ **Level Monitoring Tests**
- RMS to dB conversion
- Normalization logic

### What's NOT Tested (Requires Hardware/Mocking)

The following features require actual audio hardware or extensive mocking:

❌ **Actual Recording/Playback**
- AVAudioEngine recording
- Audio tap callbacks
- Sound playback

❌ **Hardware Integration**
- Microphone permissions
- Bluetooth device switching
- Audio format conversion (actual conversion, not calculation)

❌ **Real-time Features**
- Live audio level monitoring
- Buffer overflow handling
- Tap callback performance

These would require:
- Refactoring to use protocol-based dependency injection
- Mock AVAudioEngine implementation
- Integration test environment with microphone permissions

### Troubleshooting

**Issue: "Module 'Echo' has no member 'UnifiedAudioEngine'"**
- Ensure the Echo target has "Enable Testing" enabled (Build Settings → Enable Testability = Yes)

**Issue: "Cannot find type 'Echo' in scope"**
- Make sure `@testable import Echo` is at the top of the test file
- Verify the test file is added to the EchoTests target

**Issue: Tests fail with permission errors**
- Some tests may require microphone permissions
- Grant permissions in System Settings → Privacy & Security → Microphone

**Issue: "Undefined symbol" errors**
- Ensure AVFoundation framework is linked in test target
- Clean build folder (Cmd + Shift + K) and rebuild

### Adding More Tests

To add more tests to the suite:

1. Add new test functions with `@Test` attribute
2. Use `#expect()` for assertions (Swift Testing framework)
3. Use `async` for asynchronous tests
4. Use `@MainActor` for tests that need main actor isolation

Example:
```swift
@Test("My new test")
func myNewTest() async throws {
  #expect(someValue == expectedValue)
}
```

### Continuous Integration

To run tests in CI:

```bash
# Run tests and generate code coverage
xcodebuild -scheme Echo test \
  -enableCodeCoverage YES \
  -derivedDataPath ./build

# View code coverage report
xcrun xccov view --report ./build/Logs/Test/*.xcresult
```
