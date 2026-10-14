---
layout: ../../layouts/Page.astro
title: "Does Superwhisper Work Offline? Yes, With Local Models"
description: "Superwhisper transcribes on your Mac with local Whisper, Parakeet or Cohere models and needs no connection for that. What still needs the internet."
heading: "Does Superwhisper work offline?"
updated: "2026-10-14"
faq:
  - q: "Does Superwhisper need an internet connection?"
    a: "Not for transcription with a local model. Superwhisper's documentation says local models work without an account or an internet connection. You need to be online to download a model the first time and to use any of its cloud voice or language models."
  - q: "Which Superwhisper models work offline?"
    a: "Every Whisper model, from Tiny to Large v3 and Large v3 Turbo, all free; and on the Pro tier the two local Parakeet models and Cohere Transcribe. For the AI clean-up step, the local S1-mini model, which is English only and limited to the Message and Mail modes."
  - q: "Is Superwhisper's AI processing offline too?"
    a: "Only with S1-mini. The default S1-Language model and the OpenAI, Anthropic, Google and Groq options are cloud services, so a mode that uses them stops working without a connection even when the voice model is local."
---

Yes. Superwhisper was built around models that run on your own Mac, and with one of them selected it transcribes with no connection at all. Its documentation says plainly that local models work without an account or an internet connection, and that its Whisper models "run entirely on your device". That is the main thing that separates it from cloud-only dictation such as Wispr Flow, which [does not work offline](/articles/does-wispr-flow-work-offline).

The detail is in which parts of Superwhisper are local and which are not, because it offers both and the default clean-up step is a cloud service. This page sorts them out, from Superwhisper's documentation as of October 2026.

## What runs on the Mac

**Voice models, the part that turns speech into text.** All of these are local and work offline once downloaded:

| Model | Size | Languages | Tier |
|---|---|---|---|
| Whisper Tiny, Base, Small, Medium | 75 MB to 1.5 GB | 100+ (English-only variants too) | Free |
| Whisper Large v3 Turbo | 1.6 GB | 100+ | Free |
| Whisper Large v3 | 3 GB | 100+ | Free |
| Parakeet | 476 MB | English | Pro |
| Parakeet Multilanguage | 494 MB | 24 | Pro |
| Cohere Transcribe | 1.3 GB | 14 | Pro |

**One language model, the part that rewrites the text.** S1-mini, a 462 MB local model, runs on macOS and Windows, is English only, and "works only in Message and Mail modes".

**Your history.** Superwhisper stores transcription history on the device. Its sync feature copies configuration between your machines, "not transcription content or audio".

## What needs a connection

- **Cloud voice models:** S1-Voice, Nova 2 and 3, Nova Medical and Scribe. All Pro, all remote.
- **Cloud language models:** S1-Language, which Superwhisper calls "the default and the right choice for most modes", and the OpenAI, Anthropic, Google and Groq models, including any you add with your own API keys. A mode set to one of these fails offline even if its voice model is local.
- **Downloading a model**, once.
- **Pro features that are services in themselves**, such as translation through a cloud model.

So the trap is the clean-up step. Out of the box, a mode that formats your speech as an email probably does it through S1-Language in the cloud. If you lose the connection, the transcription still happens but the mode cannot finish.

## Setting Superwhisper up to work fully offline

1. **Choose a local voice model.** For English, Parakeet (Pro) or Whisper Large v3 Turbo (free) are the fast, accurate choices; for other languages, Whisper Large v3 or Turbo; on a Mac with little memory, Whisper Small. Download it while online.
2. **Decide what the clean-up step uses.** Either use the plain Voice mode, which transcribes without a language model, or set your modes' language model to S1-mini, accepting that it is English only and available in two modes.
3. **Test with Wi-Fi off.** Dictate into a text field. If the text appears but the formatting does not, a mode is still pointing at a cloud model.

With that done, nothing you dictate leaves the machine, which is also Superwhisper's own recommendation for sensitive material: local voice model, local language model, "no data leaves the device".

## Hardware notes

Superwhisper's current releases need macOS 14 or later. Local models run well on Apple silicon; its documentation steers Intel Macs toward cloud models, so offline use on an Intel Mac means a small, slow Whisper model. On Windows, ARM machines are told to use Parakeet or cloud models.

## The alternatives, briefly

Apple's built-in Dictation processes on the device on Apple silicon Macs, with no clean-up step. Our own [JustScribe](/guides/offline-speech-to-text-mac) is local only, with Parakeet and Whisper for speech and an on-device model for clean-up, and no cloud option to fall back to by accident. Wispr Flow has no offline mode at any price.

## Sources

Checked in October 2026: Superwhisper's [documentation](https://superwhisper.com/docs/llms-full.txt), its [voice models](https://superwhisper.com/docs/models/voice), [language models](https://superwhisper.com/docs/models/language) and [sensitive data](https://superwhisper.com/docs/security/sensitive-data) pages, and its [home page](https://superwhisper.com).
