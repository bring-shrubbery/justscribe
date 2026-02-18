<p align="center">
  <img src="justscribe/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Default-1024x1024@1x.png" alt="JustScribe app icon" width="128" />
</p>

# JustScribe

Talk. Release. Done.

JustScribe is a native macOS app for fast voice-to-text dictation anywhere on your system.
Hold one shortcut, speak naturally, and your text appears in the active app.

[Download JustScribe](https://quassum.com/apps/justscribe)

## Features

- Dictate in any app with a global shortcut
- Hold-to-record workflow with live transcription updates
- Final transcription pass on release for better accuracy
- On-device transcription with downloadable models
- Model options:
  - Parakeet v3 (recommended, multilingual)
  - Parakeet English (v2)
  - Whisper Tiny, Base, Small, Medium, Large v3
- Customizable shortcut, including modifier-only shortcuts
- Microphone priority ordering
- Recording indicator styles: Floating Bubble or Notch
- Optional automatic copy-to-clipboard
- Launch at login, Dock visibility, and Menu Bar visibility controls
- Light, Dark, and System appearance modes

## Quick Start

1. Install and open JustScribe.
2. Download and select a transcription model on first launch.
3. Grant required permissions:
   - Microphone
   - Accessibility (needed to type into other apps)
4. Put your cursor in any text field.
5. Hold the default shortcut: `Control + Shift + Space`.
6. Speak while holding.
7. Release to finish and insert final text.

You can change the shortcut, model, microphone order, and behavior in Settings.

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

- Website: [https://quassum.com/apps/justscribe](https://quassum.com/apps/justscribe)
- Privacy Policy: [https://quassum.com/apps/justscribe/privacy](https://quassum.com/apps/justscribe/privacy)
- Terms: [https://quassum.com/terms](https://quassum.com/terms)

## Contributing

Issues and pull requests are welcome.

## License

This repository currently does not include an open-source license file.
