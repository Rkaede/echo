# Changelog

## Echo 0.1.0

### ✨ New Features

#### Profiles

Set up multiple dictation profiles, each with its own shortcut, transcription model, icon and colour. Echo ships with a "General Dictation" profile on Option+Space and a "Coding" profile you can assign a shortcut to. Profiles are managed in Settings.

#### LLM Post-processing

Each profile can optionally run the transcription through a Groq-hosted LLM before pasting, to fix grammar and punctuation and strip filler words. The prompt and model are configurable per profile.

#### Notes Mode

Press Ctrl+Option+N to start a note. While Notes Mode is on, each dictation is added to a running note instead of being pasted, along with a screenshot of what was on screen (this needs Screen Recording permission). Stop Notes Mode to open the note as an HTML page (with transcript and cleaned-up views) and a Markdown file.

#### Microphone Selection

Choose a preferred input device and a fallback. Echo uses the preferred mic when it's connected, then the fallback, then the system default.

#### Sounds and Live Waveform

Echo plays a short sound when recording starts and when the transcription is pasted, and the overlay now shows a live waveform of your voice.

### 🔧 Improvements

- **Redesigned overlay**: Shows over full-screen apps and across Spaces, with clearer status and error messages.
- **Faster start**: Wired and built-in mics start recording without the extra settle delay that wireless devices need.
- **Faster paste**: The completion sound plays as soon as text is pasted; clipboard restoration happens in the background.
- **Audio engine idle timeout**: Keep the audio engine warm for between 30 seconds and 30 minutes for quicker starts.
- **Diagnostics**: Optional file logging, toggled in Settings.
- **Shortcuts**: Global shortcuts now use a built-in event tap, removing the HotKey dependency.

### 🐛 Bug Fixes

- Fixed audio format errors when Bluetooth headsets switch between playback and call modes.
- Fixed recording failing to start when the selected input device is unavailable; Echo now falls back to the system default.
- Fixed cancelled recordings occasionally being pasted, or leaving the overlay in the wrong state.
- Failed transcriptions are now recorded in History with the error that occurred.

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
