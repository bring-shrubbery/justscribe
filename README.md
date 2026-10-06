<p align="center">
  <img src="app/justscribe/Assets.xcassets/AppIcon.appiconset/Icon-macOS-Default-1024x1024@1x.png" alt="JustScribe app icon" width="128" />
</p>

<a href="https://www.producthunt.com/products/justscribe?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-justscribe" target="_blank" rel="noopener noreferrer"><img alt="JustScribe - On-device instant voice transcription | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1078541&amp;theme=light&amp;t=1773173639426"></a>

# JustScribe 😱

Native macOS app for fast voice-to-text dictation anywhere on your system. [Download here](https://justscribe.quassum.com).

## 🚀 Features

### Dictation

- Dictate in any app with a global shortcut. Hold to record, or press once to start and again to stop; the shortcut can be any combination, including modifier-only ones.
- Live transcription while you speak, then a final pass on release for accuracy. The finished text is pasted into the field you are in, or typed as you speak if you prefer.
- Spoken commands: "new line", "new paragraph", "scratch that", "delete that", "stop recording", "send", and spoken punctuation when you turn it on.
- A vocabulary for the names and words it must spell right, and clean-up modes that follow the app you dictate into.
- Optional on-device clean-up of grammar, spelling and punctuation, with Apple Intelligence (no download) or a local Llama 3.1 8B model.
- Optional copy of each dictation to the clipboard, and an optional history of your dictations, with or without the recordings (off by default; everything stays on your Mac).

### Long recordings

- **Live Transcription** records for as long as you like — a talk, a call, a meeting — from your microphone, from what other apps play (system audio), or both, and writes the transcript while it runs. With both sources, what you say is labelled "You" and the other side is told apart into Speaker 1, 2… when you stop.
- **Long Dictation** from the menu bar runs the same way with only the recording indicator, no window.
- **Transcribe File** turns an audio or video file you already have into a transcript, with timestamps and optional speaker labels.
- **Transcripts** keeps every one of them as a text file, with timestamps and speaker labels, listed by date to read, copy or show in the Finder.

### On your Mac

- Everything runs on-device: transcription, speaker identification and clean-up. Nothing is uploaded.
- Models to choose from: Parakeet v3 (recommended, multilingual), Parakeet English, Whisper Tiny to Large v3.
- A menu bar app: no Dock icon unless you want one, a confirmation before quitting, and automatic updates.
- Microphone priority order. A Bluetooth headset's microphone is used only when you put it first, so your headphones stay in full quality while you record.
- Recording indicator as a floating bubble or in the notch, with a waveform that follows your voice.
- Launch at login, light, dark and system appearance.

## 🐢 Quick Start

1. 🌟 Star this repo 🌟
2. Follow the author [Antoni (@bringshrubberyy)](https://x.com/bringshrubberyy) on X
3. Install and open JustScribe. It lives in the menu bar.
4. Download and select a transcription model on first launch.
5. Grant the permissions it asks for:
   - Microphone
   - Accessibility (needed to put text into other apps)
   - System audio recording, only if you include system audio in a Live Transcription
6. Put your cursor in any text field.
7. Hold the default shortcut: `Control + Shift + Space`.
8. Speak while holding.
9. Release to finish; the text is pasted where your cursor is.

For something longer, open the menu bar icon and choose **Live Transcription…** or **Start Long Dictation**; the transcript is saved under **Transcripts…**. You can change the shortcut, model, microphone order and behaviour in Settings.

## 🤖 Requirements

- A Mac with Apple silicon running macOS 26.2 or later
- Internet connection for the initial model download
- Microphone permission; Accessibility permission to insert text into other apps

## 😭 Development

### Open in Xcode

1. Clone this repository.
2. Open `app/justscribe.xcodeproj`.
3. Build and run the `justscribe` scheme.

## 🙈 Support

- Website: [https://justscribe.quassum.com](https://justscribe.quassum.com)
- Privacy Policy: [https://justscribe.quassum.com/privacy](https://justscribe.quassum.com/privacy)
- Terms: [https://justscribe.quassum.com/terms](https://justscribe.quassum.com/terms)

## 💀 Contributing

Issues and pull requests are welcome.

## 🐂 License

Copyright © 2026 Quassum MB.

JustScribe is licensed under the [GNU General Public License v3.0](LICENSE).
You may use, modify, and redistribute it under the terms of that license; any
distributed derivative work must also be released under the GPL-3.0.
