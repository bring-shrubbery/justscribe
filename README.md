# JustScribe

Native macOS app for instant voice-to-text transcription anywhere on your system.

Download [here](https://quassum.com/apps/justscribe)

## Features

- Global shortcut transcription (works across apps)
- Hold-to-record flow with live transcription updates
- Final transcription pass on release for better accuracy
- On-device model options:
  - Parakeet v3 (recommended, multilingual)
  - Parakeet English (v2)
  - Whisper Tiny / Base / Small / Medium / Large v3
- Customizable global shortcut (including modifier-only shortcuts)
- Microphone priority ordering
- Two recording indicator styles (Floating Bubble or Notch)
- Optional automatic copy-to-clipboard after transcription
- Launch at login + Dock/Menu Bar visibility controls
- Light, Dark, and System appearance modes

## How to Use

1. Install and open JustScribe.
2. Download and select a transcription model on first launch.
3. Grant required permissions:
   - Microphone
   - Accessibility (needed to type into other apps)
4. Place your cursor in any text field.
5. Hold the default shortcut: `Control + Shift + Space`.
6. Speak while holding the shortcut.
7. Release to finish and insert final text.

You can change the shortcut, model, microphone order, and other behavior in Settings.

## Requirements

- macOS
- Internet connection for initial model download
- Microphone permission
- Accessibility permission

## Development

### Open in Xcode

1. Clone this repository.
2. Open `justscribe.xcodeproj`.
3. Build and run the `justscribe` scheme.

### Command Line Build

```bash
xcodebuild -project justscribe.xcodeproj -scheme justscribe -configuration Debug build
```

## Support

- Website: [quassum.com/apps/justscribe](https://quassum.com/apps/justscribe)
- Privacy Policy: [quassum.com/apps/justscribe/privacy](https://quassum.com/apps/justscribe/privacy)
- Terms: [quassum.com/terms](https://quassum.com/terms)

## Contributing

Issues and pull requests are welcome.

## License

This repository currently does not include an open-source license file.
