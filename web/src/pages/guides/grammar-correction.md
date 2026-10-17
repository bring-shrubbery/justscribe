---
layout: ../../layouts/Page.astro
title: "Dictation with Grammar Correction on Mac"
description: "Fix grammar in Mac dictation: on-device with Apple Intelligence or Llama, with your own Groq, Claude or OpenAI key, or through Claude Code or Codex."
heading: "Dictation with automatic grammar correction"
updated: "2026-10-17"
faq:
  - q: "Does grammar correction send my text to a server?"
    a: "Not with the default options. Apple Intelligence and Llama 3.1 8B both run on your Mac. Only if you choose a hosted provider, or Claude Code or the Codex CLI, does the text of each dictation go to that provider; audio never leaves your Mac."
  - q: "Which grammar correction option should I use?"
    a: "Use Apple Intelligence if it is enabled on your Mac: it needs no download and no extra memory. Choose Llama 3.1 8B if Apple Intelligence is not available to you; it is a 4.6 GB download and uses about 5 GB of memory while loaded. Choose a hosted provider or a coding agent's CLI when you want a larger model and are fine with the text going to that provider."
  - q: "Can I use my Claude or ChatGPT subscription for grammar correction?"
    a: "Yes, through their command-line tools. If Claude Code or the Codex CLI is installed and signed in on your Mac, JustScribe finds it and offers it in Settings; it then corrects your dictation through your own account. If neither is installed, the option cannot be picked."
  - q: "Where is my API key stored?"
    a: "In your Mac's keychain. It is sent only to the provider you chose, never written to a settings file or log, and deleted when you press Remove."
  - q: "Will it rewrite what I said?"
    a: "It is asked only to correct grammar, spelling and punctuation, not to rephrase. Like any language model it can occasionally change a word, so reread anything important."
---

Speech models write down what they hear, including the half-sentences and missing commas of natural speech. JustScribe can clean that up for you: after you finish dictating, it passes the text through a language model on your Mac and replaces what it typed with the corrected version.

It is off by default. Dictation without it is faster, and many people do not need it.

## Turn it on

1. Open JustScribe's Settings.
2. Go to **Clean-up** and switch on **Clean Up Text**.
3. Choose a model: one of the two on your Mac, a hosted provider, or a coding agent's CLI (see below).

The Default mode fixes grammar, spelling and punctuation. You can also add modes with your own instructions and bind each to the apps it should be used in: **Settings → Clean-up → Add Mode…**. Dictation in an app with no mode of its own uses Default.

## The options

| | Apple Intelligence | Llama 3.1 8B | Hosted provider | Claude Code or Codex CLI |
|---|---|---|---|---|
| Download | None | ~4.6 GB | None | None |
| Memory while loaded | Managed by macOS | ~5 GB | None | None |
| Needs | Apple Intelligence enabled | Free memory and disk space | Your own API key | The tool installed and signed in |
| Runs | On your Mac | On your Mac | At the provider | At Anthropic or OpenAI, through your account |

**Apple Intelligence** is the default. It uses the language model that ships with macOS, so there is nothing to download. If Apple Intelligence is switched off or not available on your Mac, JustScribe says so in Settings and links to the right place to enable it.

**Llama 3.1 8B** is Meta's open model, in a compact 4-bit version that runs through Apple's MLX framework. It works on any supported Mac with memory to spare, with no dependence on Apple Intelligence.

**A hosted provider** gives you a much larger model for the price of an API key: Groq, Anthropic (Claude), OpenAI, Google Gemini, Mistral or OpenRouter. Pick the provider in **Settings → Clean-up → Hosted provider**, follow **Get an API key**, paste the key and press **Save**, then **Use**. Each provider comes with a model already filled in, and you can type another. Groq is the quickest to answer, which matters for dictation.

**Claude Code or the Codex CLI**, if you already use one of them, can do the correction through your own Anthropic or OpenAI account, with no key to paste. JustScribe looks for both when you open Settings. One that is installed gets a row with **Use** and **Try It**, which runs one correction so you can see it works before you dictate. One that is not installed is shown as such and cannot be picked. JustScribe runs the tool with its tools switched off and no session saved, and reads and writes only that tool's own settings folder.

## What happens when you dictate

1. You hold the shortcut and speak — or, in press-to-toggle mode, press it once to start; text appears as you go.
2. You release the key (or press it again in press-to-toggle mode); JustScribe transcribes the full recording again and corrects the typed text.
3. With clean-up on, the result goes to the language model with the instructions of the mode for the app you are in, and the text in your app is replaced with the corrected version.

Step 3 adds a short pause, longer for long dictations. Very long text is corrected in sentence-sized pieces so nothing is cut off. A hosted provider adds the round trip to its servers; Claude Code and the Codex CLI add a few seconds more, as the tool starts each time. If a correction fails, the dictation is kept as transcribed.

## What it changes, and what it does not

It fixes capitalisation, punctuation, spelling, and grammar slips such as a missing article or a wrong verb form. It is not asked to shorten, expand or restyle what you said, and it does not add content.

Because the corrected text replaces what was typed, keep the cursor where it is until the correction lands.

## Privacy

Apple Intelligence and Llama 3.1 8B never send your words anywhere. A hosted provider, Claude Code and the Codex CLI do send the text of each dictation to their provider, under that provider's terms, and Settings says so next to each of them; audio is never sent. API keys stay in your Mac's keychain. See the [privacy policy](/privacy) for everything JustScribe does and does not do with your data, and [offline speech to text on Mac](/guides/offline-speech-to-text-mac) for how the transcription itself works.
