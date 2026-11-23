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

Your speech is transcribed by Whisper or MAI-Transcribe-2, through OpenRouter or Groq, and automatically pasted into your current app.

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

OpenRouter and Groq are paid services.

- Whisper Large V3 Turbo: $0.04/hour
- Whisper Large V3: $0.111/hour
- MAI-Transcribe-2: about $0.10/hour
- With clean-up, the Fast setup costs about 4¢ per hour of speech and the Accurate setup about 13¢
- Groq's minimum billable duration: 10 seconds
- Typical usage: ~$1–$2/month for most people

## 🚨 Privacy (IMPORTANT)

Echo sends your audio to a cloud service to transcribe it, and the transcript too when clean-up is on. Which service depends on the models your profile uses. If privacy is a concern, consider a fully local solution (e.g., Superwhisper).

- **OpenRouter models** (what setup chooses): Echo sends the audio and the transcript to OpenRouter, which passes them to the model's host. Whisper through OpenRouter runs on Groq, so Groq's policy applies to it as well. Review OpenRouter's [Privacy Policy](https://openrouter.ai/privacy).
- **Groq models**: Echo sends them straight to Groq. Review Groq's [Privacy Policy](https://groq.com/privacy-policy) and this [community post](https://community.groq.com/help-center-14/how-does-groq-handle-my-data-190). There are inconsistencies between the policy and community statements about data retention.

What Echo does:

- Stores your Groq and OpenRouter API keys in the system keychain (never in plain text)
- Writes temporary WAV files to system temp directory (/tmp/echo/) with timestamped names, then deletes them after processing. If a transcription fails, it keeps that recording (the three most recent) in its Application Support folder so you can retry it from the menu bar.
- Uses Accessibility for the push-to-talk shortcut and to simulate Cmd+V to paste text into the current app
- When history is on, keeps each raw transcript and its cleaned text in a local SQLite database. The copy-prompt button gives a coding agent the path to it, so the agent you paste it into reads your history.

## 🤖 Models

Setup offers two pairs of models, both through OpenRouter:

- Accurate (recommended): MAI-Transcribe-2 with Gemini 3.5 Flash-Lite clean-up. English only.
- Fast: Whisper Large V3 Turbo with GPT OSS 20B clean-up. Many languages.

You can change the models for each profile in Settings › Profiles.

Transcription:

- Whisper Large V3 Turbo (OpenRouter or Groq)
- Whisper Large V3 (OpenRouter or Groq)
- MAI-Transcribe-2 (OpenRouter; English only). If it fails or is slow, Echo retries with Whisper Large V3 Turbo: on Groq if you have a Groq key, otherwise through OpenRouter.

Clean-up:

- GPT OSS 20B (OpenRouter or Groq)
- Gemini 3.5 Flash-Lite (OpenRouter)

## 📝 Requirements

- macOS 15.0+
- An OpenRouter API key, which setup asks for: https://openrouter.ai/keys
- Optional: a Groq API key. It runs Whisper and GPT OSS 20B directly on Groq, which is about 100–300 ms faster per transcription: https://console.groq.com/keys

## 🚀 Getting Started

1. Download the latest DMG: [Download for macOS](https://github.com/Rkaede/echo/releases/latest/download/Echo.dmg) (or visit the [releases page](https://github.com/Rkaede/echo/releases))
2. Open the DMG and drag the app to your Applications folder
3. Open the app and follow the setup: enter your OpenRouter API key, then choose the Accurate or the Fast models
4. Grant microphone and accessibility permissions when setup asks
5. Try a dictation: hold Fn while you talk, or tap Fn to start and tap it again to stop

To add a Groq API key, open Settings › Providers.

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
