<p align="center">
  <img width="349"  alt="echo-logo" align="center" src="https://github.com/user-attachments/assets/a6363096-0748-40a3-b9a7-979ca909cd5b" />
</p>
<p align="center">Lightning-Fast Voice-to-Text for macOS ⚡</p>


<p align="center">
  <a href="https://www.youtube.com/watch?v=vWJGuGEDd28" target="_blank">
    <img width="800" alt="Demo video" src="https://github.com/user-attachments/assets/292643b6-2382-4fd2-b31e-8662080176ca" />
  </a>
</p>

<p align="center"><a href="https://github.com/Rkaede/echo/releases/latest/download/Echo.dmg">Download</a> for macOS 15+</p>

---

A lightweight macOS app for instant speech-to-text. Press Option+Space to toggle recording or hold the Fn key for push-to-talk.

Your speech is transcribed via Groq's Whisper models, optionally cleaned up by an LLM, and automatically pasted into your current app.

- Fully open source
- Native app (no electron, no webview)
- No tracking, paywalls, or upsells

## 🌟 Features

- Minimal overlay with a live waveform, visible over full-screen apps
- Push-to-talk OR toggle to start/stop recording
- Input transcription into the current app (e.g. Slack, Cursor, etc.)
- Profiles, each with its own shortcut, transcription model, icon and colour
- Optional LLM post-processing to fix grammar and remove filler words
- Notes Mode: collect dictations and screenshots into a note, exported as HTML and Markdown
- Preferred and fallback microphone selection
- History with audio playback and full-text search

## 📉 Costs

Groq is a paid service.

- Whisper Large V3 Turbo: $0.04/hour
- Whisper Large V3: $0.111/hour
- Minimum billable duration: 10 seconds
- Roughly $10 ≈ 250 hours of audio on Turbo, or ~90 hours on Large V3
- LLM post-processing is billed separately per token and is off by default
- Typical usage: ~$1–$2/month for most people

## 🚨 Privacy (IMPORTANT)

Echo uses the Groq API to transcribe audio. Review Groq's [Privacy Policy](https://groq.com/privacy-policy) and this [community post](https://community.groq.com/help-center-14/how-does-groq-handle-my-data-190). There are inconsistencies between the policy and community statements about data retention. If privacy is a concern, consider a fully local solution (e.g., Superwhisper).

What Echo does:

- Stores your Groq API key in the system keychain (never in plain text)
- Writes temporary WAV files to system temp directory (/tmp/echo/) with timestamped names, then deletes them after processing
- Uses Accessibility for the push-to-talk shortcut and to simulate Cmd+V to paste text into the current app
- When LLM post-processing is enabled, sends the transcribed text to Groq's chat completions API
- Notes Mode only: uses Screen Recording to capture a screenshot when each dictation stops, saved with the note on your Mac

## 🤖 Models

Models can be selected per profile in the settings.

Transcription:

- Whisper Large V3 Turbo (default)
- Whisper Large V3

LLM post-processing uses Groq-hosted chat models such as GPT-OSS 20B (recommended), GPT-OSS 120B, Kimi K2 and Qwen3 32B.

## 📝 Requirements

- macOS 15.0+
- A Groq API key: https://console.groq.com

## 🚀 Getting Started

1. Download the latest DMG: [Download for macOS](https://github.com/Rkaede/echo/releases/latest/download/Echo.dmg) (or visit the [releases page](https://github.com/Rkaede/echo/releases))
2. Open the DMG and drag the app to your Applications folder
3. Open the app and follow the onboarding process
4. Grant microphone and accessibility permissions
5. Enter your Groq API key

## ⌨️ Shortcuts

- Toggle record: Option+Space (configurable per profile)
- Push-to-talk: Fn key
- Cancel recording: Escape
- Toggle Notes Mode: Ctrl+Option+N (configurable)

## 🐛 Troubleshooting

- No transcription?
  - Confirm your Groq API key is valid and saved in Settings.
- Auto-paste not working?
  - Ensure Accessibility permission is granted. Re-prompt from Settings > Permissions.
- Using a Bluetooth headset?
  - Pick a wired or built-in mic as your preferred or fallback device in Settings for faster starts.
- Overlay not visible?
  - It appears at the bottom center of the active display. Display changes are monitored; try pressing the hotkey again after focusing any app.
- Hotkeys not responding?
  - Check Option+Space isn't used by other apps or system shortcuts.
  - Fn push-to-talk, ensure Accessibility permission is granted.

## 🛣️ Roadmap

- Customizable push-to-talk key
- Automatic profile switching per app
- Per-app paste behavior (append newline, keep clipboard, etc.)
- Dictionary/word replacements
- Take screenshot for additional context

## 🤝 Contributing

Issues and PRs are welcome. Please include clear repro steps and environment details when reporting bugs.

## 📄 License

MIT
