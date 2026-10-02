---
layout: ../../layouts/Page.astro
title: "Dictation with Grammar Correction on Mac, On-Device"
description: "JustScribe can fix grammar, spelling and punctuation in dictated text on your Mac, with Apple Intelligence or a local Llama model. How to turn it on."
heading: "Dictation with automatic grammar correction"
updated: "2026-10-02"
faq:
  - q: "Does grammar correction send my text to a server?"
    a: "No. Both options run on your Mac. The Apple Intelligence option uses the language model built into macOS, and the Llama option uses a model file downloaded to your Mac."
  - q: "Which grammar correction option should I use?"
    a: "Use Apple Intelligence if it is enabled on your Mac: it needs no download and no extra memory. Choose Llama 3.1 8B if Apple Intelligence is not available to you; it is a 4.6 GB download and uses about 5 GB of memory while loaded."
  - q: "Will it rewrite what I said?"
    a: "It is asked only to correct grammar, spelling and punctuation, not to rephrase. Like any language model it can occasionally change a word, so reread anything important."
---

Speech models write down what they hear, including the half-sentences and missing commas of natural speech. JustScribe can clean that up for you: after you finish dictating, it passes the text through a language model on your Mac and replaces what it typed with the corrected version.

It is off by default. Dictation without it is faster, and many people do not need it.

## Turn it on

1. Open JustScribe's Settings.
2. Go to **Grammar Correction** and switch it on.
3. Choose a model.

## The two models

| | Apple Intelligence | Llama 3.1 8B |
|---|---|---|
| Download | None | ~4.6 GB |
| Memory while loaded | Managed by macOS | ~5 GB |
| Needs | Apple Intelligence enabled in System Settings | Enough free memory and disk space |
| Runs | On your Mac | On your Mac |

**Apple Intelligence** is the default. It uses the language model that ships with macOS, so there is nothing to download. If Apple Intelligence is switched off or not available on your Mac, JustScribe says so in Settings and links to the right place to enable it.

**Llama 3.1 8B** is Meta's open model, in a compact 4-bit version that runs through Apple's MLX framework. It works on any supported Mac with memory to spare, with no dependence on Apple Intelligence.

## What happens when you dictate

1. You hold the shortcut and speak; text appears as you go.
2. You release the key; JustScribe transcribes the full recording again and corrects the typed text.
3. With grammar correction on, the result goes to the language model, and the text in your app is replaced with the corrected version.

Step 3 adds a short pause, longer for long dictations. Very long text is corrected in sentence-sized pieces so nothing is cut off.

## What it changes, and what it does not

It fixes capitalisation, punctuation, spelling, and grammar slips such as a missing article or a wrong verb form. It is not asked to shorten, expand or restyle what you said, and it does not add content.

Because the corrected text replaces what was typed, keep the cursor where it is until the correction lands.

## Privacy

Neither model sends your words anywhere. See the [privacy policy](/privacy) for everything JustScribe does and does not do with your data, and [offline speech to text on Mac](/guides/offline-speech-to-text-mac) for how the transcription itself works.
