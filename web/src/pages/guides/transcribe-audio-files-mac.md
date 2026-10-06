---
layout: ../../layouts/Page.astro
title: "Transcribe Audio and Video Files on a Mac, Free"
description: "Turn a recording or a video into a transcript on your Mac with JustScribe: timestamps on every paragraph, optional speaker labels, nothing uploaded, no account."
heading: "Transcribe audio and video files on a Mac"
updated: "2026-10-03"
faq:
  - q: "Can JustScribe transcribe a recording, not just dictation?"
    a: "Yes. Choose Transcribe File from the menu-bar icon, drop in an audio or video file, and you get a transcript with a timestamp on each paragraph. It runs on your Mac with the same models as dictation."
  - q: "Does it label who is speaking?"
    a: "Yes, when you turn on Identify speakers. Paragraphs are labelled Speaker 1, Speaker 2 and so on. Leave the count empty to detect it, or enter how many people are in the recording. Labels are never names, and like all speaker detection it sometimes gets a line wrong."
  - q: "Which file types work?"
    a: "Anything macOS can play: m4a, mp3, wav, aiff, caf and flac, and the audio track of mp4, mov and m4v videos. Copy-protected media cannot be transcribed."
  - q: "Is the file uploaded anywhere?"
    a: "No. The file is read where it is and transcribed on your Mac. When speakers are identified, a temporary decoded copy of the audio is written inside the app's own container and deleted afterwards. The transcript is also saved as a text file in the app's own container, where the Transcripts window lists it; move it to the Trash from there if you don't want to keep it."
  - q: "How long does it take?"
    a: "With Parakeet v3 on an Apple silicon Mac, usually faster than real time. Identifying speakers adds a pass of its own before the transcription. Large Whisper models are slower."
---

JustScribe is a dictation app first, but the same on-device models can transcribe a file you already have: an interview, a lecture, a voice memo, a meeting recording, or the audio of a video.

## Transcribe a file

1. Click the JustScribe icon in the menu bar and choose **Transcribe File…**
2. Drop an audio or video file on the window, or click **Choose File…**
3. Optionally turn on **Identify speakers**. The first time, a small speaker model (about 22 MB) is downloaded. Leave the count empty to detect it, or enter the number of people.
4. Watch the transcript fill in, paragraph by paragraph. **Copy** it, or **Save…** it as a text file. It is also kept in the **Transcripts** window, reachable from the menu-bar icon.

The transcript looks like this:

```
[00:00:04] Speaker 1
So the first thing we looked at was the onboarding flow,
and where people dropped off.

[00:00:19] Speaker 2
Right, and that was mostly at the permissions step?
```

With speakers off, or when only one voice is found, you get the same paragraphs with just the times.

## What you can do while it runs

Keep dictating. JustScribe processes the file a piece at a time and pauses between pieces whenever you hold the dictation shortcut, so your dictation never waits for the file. **Cancel** stops after the current piece and keeps the text so far.

## Models and languages

A file is transcribed with the model and language you chose for dictation. Parakeet v3 is the fast, multilingual default. The Whisper models are slower and some people find them more accurate on difficult audio. See [offline speech to text on a Mac](/guides/offline-speech-to-text-mac) for the list.

Speaker identification is separate from the transcription model and works with any of them.

## Limits worth knowing

- One file at a time, and plain text output. There is no subtitle (SRT) export yet, and no batch mode.
- Speaker labels are Speaker 1, Speaker 2, …, assigned in the order people first talk. Overlapping speech and similar voices can confuse them.
- Long recordings work (hours), but identifying speakers on them takes a while and uses a few hundred megabytes of memory while it runs.
- Grammar correction is not applied to file transcripts.

Compared with dedicated transcription apps such as [MacWhisper](/macwhisper-alternative) and [Superwhisper](/superwhisper-alternative), JustScribe's file transcription is simpler: no formats to choose, no cloud models, nothing to buy.
