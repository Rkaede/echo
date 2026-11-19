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

A lightweight macOS app for instant speech-to-text. Tap Fn to record hands-free, or hold Fn for push-to-talk. Recording uses the active profile.

Your speech is transcribed via Groq's Whisper models, or MAI-Transcribe-2 through OpenRouter, and automatically pasted into your current app.

- Fully open source
- Native app (no electron, no webview)
- No tracking, paywalls, or upsells

## 🌟 Features

- Minimal overlay
- Push-to-talk OR toggle to start/stop recording
- Input transcription into the current app (e.g. Slack, Cursor, etc.)
- History with audio playback and full-text search
- Optional clean-up of each dictation by an LLM (punctuation, filler and misheard names), set per profile
- A copy-prompt button that has a coding agent such as Claude Code review your history and suggest a better clean-up prompt

## 📉 Costs

Groq and OpenRouter are paid services.

- Whisper Large V3 Turbo (Groq): $0.04/hour
- Whisper Large V3 (Groq): $0.111/hour
- MAI-Transcribe-2 (OpenRouter): about $0.10/hour
- Groq's minimum billable duration: 10 seconds
- Typical usage: ~$1–$2/month for most people

## 🚨 Privacy (IMPORTANT)

Echo uses the Groq API to transcribe audio. Review Groq's [Privacy Policy](https://groq.com/privacy-policy) and this [community post](https://community.groq.com/help-center-14/how-does-groq-handle-my-data-190). There are inconsistencies between the policy and community statements about data retention. If privacy is a concern, consider a fully local solution (e.g., Superwhisper).

If you choose an OpenRouter model, Echo sends the audio (MAI-Transcribe-2) or the transcript text (Gemini clean-up) to OpenRouter, which passes it to the model's host. Review OpenRouter's [Privacy Policy](https://openrouter.ai/privacy).

What Echo does:

- Stores your Groq and OpenRouter API keys in the system keychain (never in plain text)
- Writes temporary WAV files to system temp directory (/tmp/echo/) with timestamped names, then deletes them after processing. If a transcription fails, it keeps that recording (the three most recent) in its Application Support folder so you can retry it from the menu bar.
- Uses Accessibility for the push-to-talk shortcut and to simulate Cmd+V to paste text into the current app
- When history is on, keeps each raw transcript and its cleaned text in a local SQLite database. The copy-prompt button gives a coding agent the path to it, so the agent you paste it into reads your history.

## 🤖 Models

Models are chosen per profile in Settings › Profiles.

Transcription:

- Whisper Large V3 Turbo (Groq, default)
- Whisper Large V3 (Groq)
- MAI-Transcribe-2 (OpenRouter; English only). If it fails or is slow, Echo retries with Whisper Large V3 Turbo on Groq.

Clean-up:

- GPT OSS 20B (Groq, default)
- Gemini 3.5 Flash-Lite (OpenRouter)

## 📝 Requirements

- macOS 15.0+
- A Groq API key: https://console.groq.com
- Optional: an OpenRouter API key for MAI-Transcribe-2 and Gemini: https://openrouter.ai/keys

## 🚀 Getting Started

1. Download the latest DMG: [Download for macOS](https://github.com/Rkaede/echo/releases/latest/download/Echo.dmg) (or visit the [releases page](https://github.com/Rkaede/echo/releases))
2. Open the DMG and drag the app to your Applications folder
3. Open the app and follow the onboarding process
4. Grant microphone and accessibility permissions
5. Enter your Groq API key

## ⌨️ Shortcuts

- Hands-free recording: tap and release Fn within 300 ms; press Fn again to stop.
- Push-to-talk: hold Fn for 300 ms or longer; release to stop.
- Previous profile recording shortcuts are preserved but inactive. Profile navigation remains available while recording.

## 🐛 Troubleshooting

- No transcription?
  - Confirm the API key for the profile's model (Groq or OpenRouter) is valid and saved in Settings.
- Auto-paste not working?
  - Ensure Accessibility permission is granted. Re-prompt from Settings > Permissions.
- Overlay not visible?
  - It appears at the bottom center of the active display. Display changes are monitored; try pressing the hotkey again after focusing any app.
- Hotkeys not responding?
  - Check the macOS Fn/Globe setting for conflicting system actions.
  - Fn recording, ensure Accessibility permission is granted.

## 🛣️ Roadmap

- Profiles with configurable recording settings and profile navigation shortcuts
- LLM post processing
- Per-app paste behavior (append newline, keep clipboard, etc.)
- Dictionary/word replacements
- Take screenshot for additional context

## 🤝 Contributing

Issues and PRs are welcome. Please include clear repro steps and environment details when reporting bugs.

## 📄 License

MIT
