<p align="center">
  <img width="549" height="208" alt="echo-logo" align="center" src="https://github.com/user-attachments/assets/a6363096-0748-40a3-b9a7-979ca909cd5b" />
</p>
<p align="center">Lightning-Fast Voice-to-Text for macOS ⚡</p>



<p align="center">
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="MIT License">
  </a>
</p>

---


A lightweight macOS app for instant speech-to-text. Press Option+Space to toggle recording or hold the Fn key for push-to-talk.

Your speech is transcribed via Groq's Whisper models and automatically pasted into your current app.

- Fully open source
- Native app (no electron, no webview)
- No tracking, paywalls, or upsells

## 🌟 Features

- Minimal overlay
- Push-to-talk OR toggle to start/stop recording
- Input transcription into the current app (e.g. Slack, Cursor, etc.)

## 📉 Costs

Groq is a paid service.

- Whisper Large V3 Turbo: $0.111/hour
- Minimum billable duration: 10 seconds
- Roughly $10 ≈ 90 hours of audio, or ~32,400 10-second chunks
- Typical usage: ~$1–$2/month for most people

## 🚨 Privacy (IMPORTANT)

Echo uses the Groq API to transcribe audio. Review Groq's [Privacy Policy](https://groq.com/privacy-policy) and this [community post](https://community.groq.com/help-center-14/how-does-groq-handle-my-data-190). There are inconsistencies between the policy and community statements about data retention. If privacy is a concern, consider a fully local solution (e.g., Superwhisper).

What Echo does:

- Stores your Groq API key in the system keychain (never in plain text)
- Writes temporary WAV files to system temp directory (/tmp/echo/) with timestamped names, then deletes them after processing
- Uses Accessibility for the push-to-talk shortcut and to simulate Cmd+V to paste text into the current app

## 🤖 Models

Models can be selected in the settings.

- Whisper Large V3
- Whisper Large V3 Turbo
- Distil-Whisper English

## 📝 Requirements

- macOS 15.0+
- A Groq API key: https://console.groq.com

## 🚀 Getting Started

1. Download the latest release from the [releases page](https://github.com/Rkaede/echo/releases)
2. Open the DMG and drag the app to your Applications folder
3. Open the app and follow the onboarding process
4. Grant microphone and accessibility permissions
5. Enter your Groq API key

## ⌨️ Shortcuts

- Toggle record: Option+Space
- Push-to-talk: Fn key

## 🐛 Troubleshooting

- No transcription?
  - Confirm your Groq API key is valid and saved in Settings.
- Auto-paste not working?
  - Ensure Accessibility permission is granted. Re-prompt from Settings > Permissions.
- Overlay not visible?
  - It appears at the bottom center of the active display. Display changes are monitored; try pressing the hotkey again after focusing any app.
- Hotkeys not responding?
  - Check Option+Space isn't used by other apps or system shortcuts.
  - Fn push-to-talk, ensure Accessibility permission is granted.

## 🛣️ Roadmap

- Bug fixes
- Cancel recording
- Restore clipboard after pasting
- LLM post processing
- Profiles with Customizable hotkey and push-to-talk keys
- Per-app paste behavior (append newline, keep clipboard, etc.)
- Dictionary/word replacements
- Take screenshot for additional context
- History

## 🤝 Contributing

Issues and PRs are welcome. Please include clear repro steps and environment details when reporting bugs.

## 📄 License

MIT
