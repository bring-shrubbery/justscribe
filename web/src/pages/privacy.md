---
layout: ../layouts/Page.astro
title: "JustScribe Privacy Policy"
description: "JustScribe transcribes on your Mac and has no servers: your audio and text are never collected. What the app and this website do and do not do with your data."
heading: "JustScribe Privacy Policy"
updated: "2026-10-03"
download: false
---

## In short

- JustScribe processes all audio on your Mac.
- No audio and no transcribed text is ever sent to us or to anyone else.
- We do not collect, store, or have access to anything you dictate.
- The app has no analytics, no tracking and no account.
- Dictation works without an internet connection once a model is downloaded.

## Who we are

JustScribe ("the App") is made by Quassum MB, Algirdo 18-11, LT-03218 Vilnius, Lithuania ("Quassum", "we"). This policy covers the App and the website at justscribe.quassum.com.

## What the App does not collect

JustScribe is designed so that we cannot see what you do with it. We do not collect — unless you turn on History, which keeps them on your Mac only (see below):

- Audio recordings or voice data
- Transcribed text
- Usage patterns within the App
- Personal information
- Device identifiers
- Location data

## How the App works

JustScribe uses on-device machine learning models (Parakeet and Whisper) to transcribe audio. All processing happens on your Mac:

- Audio is held in memory while you record and discarded afterwards. It is not saved to disk.
- Audio is never uploaded. We do not operate transcription servers.
- Optional grammar correction also runs on your Mac, using either the language model built into macOS (Apple Intelligence) or a Llama model stored on your Mac.
- Files you transcribe are read where they are and never uploaded. When you ask for speakers to be identified, the App writes a temporary copy of the file's audio inside its own sandbox container and deletes it when the pass ends; if the App was quit or failed meanwhile, the copy is removed the next time the App starts or identifies speakers. The transcript is discarded when you close the window unless you copy or save it.

## What is stored on your Mac

Your settings, and the model files you download, are stored on your Mac in the App's sandbox container. This data is only accessible to the App, is not synced by us to any service, and is removed when you delete the App's data.

## When the App uses the network

The App contacts the internet in three cases. None of them sends audio or text.

- **Downloading a model.** When you choose a transcription model, the optional Llama grammar model, or turn on speaker identification for file transcription, the App downloads it from Hugging Face (huggingface.co). As with any download, Hugging Face sees your IP address and which file was requested. Their handling of that request is covered by their own privacy policy.
- **Checking for updates.** The App checks for a new version when it starts and about once a day. The check requests a small file from justscribe.quassum.com, which redirects to GitHub (github.com), and a newer version is downloaded from GitHub. Those services see your IP address and the App's version. You can turn automatic updates off in Settings; a manual check makes the same requests.
- **Links you open.** Links in Settings, such as this policy or the sponsor page, open in your browser.

The App sends nothing else, and nothing to us directly.

## Microphone permission

JustScribe needs microphone access to hear what you dictate. It records only while you hold the shortcut or choose Start Transcription in the menu. You can revoke the permission at any time in System Settings.

## Accessibility permission

JustScribe needs Accessibility permission to type the transcribed text into the app you are using. It is used only to insert text at your cursor. It is not used to read the content of other apps or to monitor your keyboard. You can revoke it at any time in System Settings.

## History (optional)

History is off unless you turn it on in Settings → History.

- **Keep Transcriptions** saves the text of each dictation, with the date, its length and the model used.
- **Keep Audio Recordings** also saves the recording as a small audio file. Recordings are removed oldest first once they pass 1 GB.

Everything History keeps is stored inside the App's own container on your Mac. It is never uploaded or synced by the App. **Delete All History** in Settings removes all of it; turning a switch off keeps what already exists until you delete it.

## This website

justscribe.quassum.com is a static site served by Cloudflare. It sets no cookies and runs no analytics or tracking scripts. Like any web host, Cloudflare processes the technical data of each request (such as IP address, browser type and the page requested) to deliver the site and protect it from abuse. The download button links to files hosted on GitHub.

## Children

JustScribe does not knowingly collect personal information from children, because it does not collect personal information from anyone.

## Your rights

Because we hold no personal data about App users, there is nothing for us to give access to, correct or delete. You remain in control of the models and settings on your Mac, of the App's permissions, and of the App itself. If you contact us by email, we keep that correspondence only as long as needed to answer you, and you can ask us to delete it.

## Changes to this policy

When we change this policy we will publish the new version on this page and update the date at the top.

## Contact

Questions about this policy: [info@quassum.com](mailto:info@quassum.com).
