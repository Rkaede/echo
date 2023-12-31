# Echo

Local transcription using OpenAI's Whisper models. Transcriptions are sent to the active window.

## Installation

Download the dmg file from the releases page and run to install.

Echo is currently only tested on macOS (arm64). PRs to add support for other platforms are welcome.

## Usage

Press `option + space` to start recording. Press again to stop recording. The transcription will be sent to the active window.

Please note: You will be prompted to allow microphone and accessibility permissions on first use. After allowing access, you will need to restart Echo.

## Roadmap

- Audio cues (done)
- Text replacement
- Permissions onboarding
- ffmpeg processing (noise reduction, silence removal etc.)
- History
- Custom prompt support (basic)
- Customizable hotkey
- Audio device selection
- Profiles
- Distil models
- LLM support
- Overlay updates
- Linux & Windows support
