---
layout: ../../layouts/Page.astro
title: "Offline Speech to Text on Mac: Models and Setup"
description: "Offline speech to text on a Mac with JustScribe: which on-device model to pick, Parakeet or Whisper, how big each is, and what happens to your audio."
heading: "Offline speech to text on a Mac"
updated: "2026-10-02"
faq:
  - q: "Can a Mac do speech to text without the internet?"
    a: "Yes. Apple silicon Macs are fast enough to run modern speech recognition models locally. With JustScribe you download a model once, and after that dictation works with no connection at all."
  - q: "Which model should I choose for dictation?"
    a: "Start with Parakeet v3. It is the recommended model: about 250 MB, multilingual, and fast enough that text appears while you are still speaking. Try a larger Whisper model only if it makes mistakes on your voice or language."
  - q: "Is anything uploaded when I dictate?"
    a: "No. The audio is transcribed by the model on your Mac and discarded. JustScribe has no servers to send it to. The only downloads are the model files themselves, once, and update checks."
---

Speech recognition used to mean sending audio to a server. On an Apple silicon Mac it no longer has to: the models are small enough, and the chips fast enough, to transcribe as you speak. JustScribe is a free app that does exactly this for dictation.

## Set it up

1. [Download JustScribe](/download) and open it.
2. Choose a model. It is downloaded once, from Hugging Face, and stored on your Mac.
3. Allow Microphone access, to hear you, and Accessibility access, to type into other apps.
4. Hold `Control` `Shift` `Space`, speak, and release.

From then on you can turn Wi-Fi off and it keeps working.

## The models

| Model | Download | Languages | Choose it when |
|---|---|---|---|
| Parakeet v3 | ~250 MB | Multilingual | You want the default: fast and accurate |
| Parakeet English | ~200 MB | English | You only dictate in English |
| Whisper Tiny | ~75 MB | Multilingual | Disk space is very tight |
| Whisper Base | ~142 MB | Multilingual | You want Whisper at a small size |
| Whisper Small | ~466 MB | Multilingual | A middle ground |
| Whisper Medium | ~1.5 GB | Multilingual | Accuracy matters more than speed |
| Whisper Large v3 | ~3 GB | Multilingual | You want Whisper's best accuracy and have the memory for it |

Parakeet is a speech model from NVIDIA, run on the Mac through [FluidAudio](https://github.com/FluidInference/FluidAudio). Whisper is OpenAI's open speech model, run through [WhisperKit](https://github.com/argmaxinc/WhisperKit). Both are converted to run on Apple's own machine-learning hardware.

You can download several models and switch between them in Settings at any time.

## What happens when you dictate

While you hold the shortcut, JustScribe records from your microphone and transcribes what it has so far every couple of seconds, typing the new words into the focused app. When you release the key it transcribes the whole recording once more, which is more accurate than the live pass, and corrects the text it typed.

The audio stays in memory for the length of the recording and is then thrown away. It is never written to disk and never sent anywhere.

## What "offline" does not cover

Three things use the network, and none of them carries your voice:

- **Downloading a model**, once, when you pick it.
- **Checking for updates**, once a day. You can turn automatic updates off in Settings.
- **Downloading the optional Llama model** for [grammar correction](/guides/grammar-correction), if you choose it.

## Requirements

An Apple silicon Mac (M1 or newer) with macOS 26.2 or later. Intel Macs are not supported: the models rely on Apple's Neural Engine and GPU.
