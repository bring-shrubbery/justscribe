---
layout: ../../layouts/Page.astro
title: "What Is Wispr Flow? How the Dictation App Works"
description: "Wispr Flow is an AI dictation app: hold a key, speak, and edited text appears in any app. What it does, what it costs, where your voice goes and who makes it."
heading: "What is Wispr Flow, and how does it work?"
updated: "2026-10-13"
faq:
  - q: "Is Wispr Flow free?"
    a: "There is a free plan with a weekly limit: 2,000 dictated words a week on Mac and Windows and 1,000 on a phone, as of October 2026. Flow Pro removes the limit for $15 a month, or $12 a month paid yearly."
  - q: "Does Wispr Flow work offline?"
    a: "No. Wispr Flow's documentation says transcription always happens in the cloud, so it needs an internet connection every time you dictate."
  - q: "Is Wispr Flow the same as Whisper?"
    a: "No. Whisper is OpenAI's open-source speech recognition model. Wispr Flow is a product from a company called Wispr, which runs its own speech model on its servers. The similar names do not mean shared technology."
  - q: "Which devices does Wispr Flow run on?"
    a: "Mac (macOS 12 or later, Intel or Apple silicon), Windows 10 and 11 on x64 processors, iPhone (iOS 18.3 or later) and Android 13 or later. There is no version for iPad, Linux or Chromebooks."
---

Wispr Flow is a dictation app. You hold a key, say what you want to write, and let go; a moment later the text appears wherever your cursor was, with the "um"s removed, punctuation added and false starts tidied up. It runs on Mac, Windows, iPhone and Android, and it works in any app that takes text: email, chat, documents, code editors, browsers.

It is made by Wispr, a San Francisco company, and it has become the best-known app of its kind. This page explains what it does, how it does it, what it costs, where your voice goes and where it came from, so you can decide whether it suits you. Everything here comes from Wispr's own site and help centre as of October 2026; the sources are listed at the end.

## How a dictation works

1. **Hold the shortcut.** On a Mac it is the `Fn` key by default (`Control` `Option` on Macs without an Fn key); on Windows it is `Ctrl` `Win`. Put the cursor where the text should go first.
2. **Speak.** A small "Flow Bar" shows that it is listening. You can whisper if you share an office; Flow is tuned for quiet speech.
3. **Let go.** The audio has been streaming to Wispr's servers while you spoke. They transcribe it, clean it up and send the text back.
4. **The text is inserted** into the field that has focus. To throw a dictation away instead, press `Esc` before it lands.

Hands-free mode is for longer stretches: press `Fn` `Space` (or double-tap the hold key within half a second), talk for up to 20 minutes, and press the shortcut again to stop. It also ends on its own when it hears nothing for a while.

Wispr says this is four times faster than typing. The app's premise is that for most text, talking is easier than typing, provided something tidies up the result.

## What the AI editing does

Plain speech recognition writes down everything, including "um, so, actually no, scratch that". Wispr Flow's selling point is what happens after recognition:

- **Filler and false starts are removed**, and corrections you make mid-sentence are applied: "Tuesday, no, Wednesday" becomes "Wednesday".
- **Punctuation, paragraphs and lists** are added.
- **Tone follows the app.** There are three styles, formal, casual and very casual, and each app can have its own.
- **It reads the context.** Context Awareness looks at the app you are in, the text before and after your cursor and the names on screen, so "reply to Sam" gets the spelling of the Sam you are messaging. Wispr's help centre says it works from text and does not take screenshots, that it skips password fields and financial apps, and that the captured text is cleared when the dictation ends. It is on by default and can be turned off under Settings → Data and Privacy.
- **It learns names and jargon.** A personal dictionary holds words it should spell your way, and Flow adds to it from your corrections. Snippets expand a short spoken phrase into a block of text.

Beyond dictation there is a **Command Mode**, which rewrites selected text from a spoken instruction ("make this more formal", "turn this into bullet points"); it is marked experimental and needs a paid plan. **Wispr Notetaker**, added in 2026, records meetings on Mac and Windows without joining the call as a bot and produces a transcript, a summary and action items. The app can also hand text to ChatGPT and Claude.

## Languages

Wispr Flow understands more than 100 languages and switches between them as you speak, so a sentence that mixes two languages comes out as spoken.

## Where it runs

| Platform | Requirements |
|---|---|
| Mac | macOS 12 Monterey or later; separate downloads for Apple silicon and Intel; 8 GB of memory recommended |
| Windows | Windows 10 or 11 on an x64 processor; ARM and Snapdragon machines are not supported |
| iPhone | iOS 18.3 or later, as a keyboard; there is no iPad version |
| Android | Android 13 or later, on phones |

Linux, Chromebooks, virtual machines and remote desktops are not supported. Every version needs a working microphone and an internet connection.

## What it costs

| Plan | Price per user | What you get |
|---|---|---|
| Free | $0 | 2,000 dictated words a week on desktop, 1,000 on mobile; all the dictation features; limited Notetaker history |
| Pro | $15 a month, or $12 a month paid yearly | Unlimited dictation, a team workspace, shared dictionary and snippets |
| Growth | $23 a month, or $18 a month paid yearly | Single sign-on, HIPAA enforcement for the organisation, admin controls |
| Enterprise | Custom | SCIM, audit logs, model-training settings locked off |

The weekly allowance resets on Sunday at midnight Pacific time, and unused words do not carry over. The details, including students and how to cancel, are in [Wispr Flow pricing explained](/articles/wispr-flow-pricing).

## Where your voice goes

Wispr Flow is a cloud service. Its data controls page says: "Transcription always occurs on the cloud." Audio is streamed to Wispr's servers, transcribed there and, unless you have turned on cloud storage of your dictations, deleted once the transcript exists. The text goes through Wispr's own models and third-party AI providers, with which Wispr says it has zero-data-retention agreements. You choose whether your dictations may be used to improve Wispr's models, whether they are stored in the cloud and synced between devices, and whether Context Awareness is on.

Two consequences follow. It does not work offline: see [Does Wispr Flow work offline?](/articles/does-wispr-flow-work-offline). And everything you dictate leaves your machine, which may or may not matter for your work: [Is Wispr Flow private?](/articles/wispr-flow-privacy) goes through the settings and policies in detail.

## Who makes it

Wispr was founded in 2021 by Tanay Kothari and Sahaj Garg. For its first three years it worked on a wearable that would let people type by mouthing words silently. In 2024 it released Flow as software for the Mac, followed by Windows, iPhone and, in February 2026, Android.

The company has raised $361 million: $30 million led by Menlo Ventures in June 2025, a $25 million extension led by Notable Capital in November 2025, and a $280 million Series B led by Menlo Ventures in August 2026 at a $2 billion valuation. It says more than 60 billion words have been written with Flow. Alongside the Series B it announced a speech model of its own, which it says makes far fewer mistakes in noisy rooms, and the Notetaker.

Despite the name, Wispr Flow does not use Whisper, OpenAI's open-source speech model, and is unrelated to it.

## How it compares

Every Mac, PC and phone has dictation built in, and it is free; Apple's can run on the device. Wispr Flow's case against it is the editing, the dictionary, the same behaviour on every device, and the whispering. Against other third-party apps the dividing line is mostly cloud versus local: Wispr Flow does everything on its servers, while apps such as Superwhisper, MacWhisper and our own [JustScribe](/wispr-flow-alternative) can run the speech model on the Mac itself. Choose by what you dictate and where you dictate it.

## Sources

Checked in October 2026: Wispr Flow's [home page](https://wisprflow.ai), [pricing](https://wisprflow.ai/pricing) and [data controls](https://wisprflow.ai/data-controls); its help centre on [starting a dictation](https://docs.wisprflow.ai/articles/6409258247-starting-your-first-dictation), [hands-free mode](https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free), [Context Awareness](https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness), [Command Mode](https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode) and [system requirements](https://docs.wisprflow.ai/articles/1036674442-supported-devices-and-system-requirements); Wispr's [Series B announcement](https://wisprflow.ai/post/series-b); [TechCrunch, 17 August 2026](https://techcrunch.com/2026/08/17/wispr-raises-280m-at-2b-valuation-as-it-looks-beyond-dictation/); [Wikipedia](https://en.wikipedia.org/wiki/Wispr_Flow).
