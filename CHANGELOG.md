# Changelog

## Echo 0.0.3

### Recording Shortcut Change

Option+Space no longer starts a recording. Recording now uses the Fn key:

- **Tap Fn** to record hands-free, then press Fn again to stop.
- **Hold Fn** to talk, and release it to stop.

Recordings use the active profile. Hotkeys saved on profiles are kept but no longer active. If pressing Fn opens the emoji picker or dictation, change what the Globe (Fn) key does in System Settings › Keyboard.

### New Features

#### Notes Mode

Dictate a series of notes instead of pasting text. Turn notes mode on with Ctrl+Option+N or from the menu bar, and each recording is added to the note with a screenshot of your screen. When you stop, the note opens as a page with the full note and screenshots, the plain transcript and an AI-cleaned-up version, each ready to copy. A Markdown copy is saved alongside it.

  - Hold Shift while recording to draw on the screen. The drawing goes into that entry's screenshot, which is cropped to the area you marked.
  - A notes bar above the recording overlay shows the entry count and the last entry, with a stop button.
  - Screenshots need the Screen Recording permission.

#### Profiles

Create profiles with their own transcription model, an optional AI post-processing prompt, and a custom icon and colour. Switch to the previous or next profile while recording using shortcuts you can set in Settings.

#### Sounds

Optional sounds play when recording starts and when a transcription completes. Pick the sounds or turn them off in Settings.

#### Microphone Selection

Choose a preferred microphone and a fallback. Echo uses the preferred microphone, then the fallback, then the system default.

### Improvements

- **No more phantom text**: accidental or silent recordings are dropped instead of pasting stock phrases like "Thank you."
- **Smoother overlay**: the recording overlay appears faster, and its live waveform works across microphones and stays smooth in long sessions.
- **Faster start**: recording starts sooner with wired microphones, and the completion sound plays as soon as the text is pasted.
- **Idle timeout**: choose how long the microphone stays ready after a recording, from 30 seconds to 30 minutes.
- **Clearer errors**: the overlay says what kind of problem occurred, such as network, API key, permission or audio.
- **Diagnostic logs**: Settings › Troubleshooting › Open Logs Folder.
- **Updates**: Echo checks for updates from launch, not only after Settings has been opened.

### Bug Fixes

- Fixed recording when a Bluetooth headset switches audio modes.
- Made cancelling with Escape and starting a recording more reliable.
- The overlay now stays visible across Spaces and over full-screen apps.

## Echo 0.0.2

### ✨ New Features

#### History

You can now browse and search all past transcriptions. Highlights include:

  - Each transcription includes detailed metadata (model used, duration, current app, timing metrics).
  - Search transcriptions with full text search.
  - Save and playback source audio with each transcription. This is disabled by default. Configurable in the settings.

The History window is available from the menu bar dropdown.

#### Recording Cancellation

Press Escape to cancel recording mid-session. 

#### Clipboard Restoration

Automatically restores previous clipboard content after pasting transcriptions. This is enabled by default. Configurable in Settings.

### 🔧 Improvements

- **Permission Handling**: Better management of microphone and accessibility permissions.
- **Settings UI Polish**: General improvements to the settings interface.

### 🐛 Bug Fixes

- Improved error handling for recording failures and permission issues

## 0.0.1

- First release 🚀
