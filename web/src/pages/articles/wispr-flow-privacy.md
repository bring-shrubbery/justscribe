---
layout: ../../layouts/Page.astro
title: "Is Wispr Flow Private? Where Your Audio and Text Go"
description: "What Wispr Flow does with your voice: transcription on its servers, what is kept, who else processes it, the settings that matter, and how to delete your data."
heading: "Is Wispr Flow private? Where your audio and text go"
updated: "2026-10-13"
faq:
  - q: "Does Wispr Flow record everything I say?"
    a: "It listens only while you hold the shortcut or a hands-free session is running. During that time the audio is streamed to Wispr's servers, because that is where transcription happens. Wispr says the audio is deleted as soon as it has been transcribed unless you turn on cloud storage of your dictations."
  - q: "Does Wispr Flow take screenshots?"
    a: "Wispr's help centre says Context Awareness works from text and does not take screenshots. It does read the name of the app, the text around your cursor and names on screen, and sends them with your dictation. You can turn it off in Settings, Data and Privacy."
  - q: "Does Wispr Flow use my dictations to train its models?"
    a: "Only if the model-improvement setting is on for your account. When it is, Wispr says your audio, transcripts and edits may be used to evaluate, train or improve its models. Check Settings, Data and Privacy. On Enterprise plans the setting is off and locked."
  - q: "Can I keep my dictations off Wispr's servers entirely?"
    a: "No. Transcription always happens on Wispr's servers, so every dictation passes through them. The settings decide what is kept afterwards, not whether it is sent."
---

Short answer: your voice leaves your computer every time you dictate. Wispr Flow streams the audio to its servers, transcribes it there and runs the text through AI models, its own and third parties', to produce the edited result. Wispr's data controls page puts it plainly: "Transcription always occurs on the cloud." No setting changes that. What happens afterwards, whether anything is stored, who else handles it and whether it trains models, depends on settings you should look at once.

This page goes through what leaves your device, what Wispr keeps, who else processes it, which settings to check and how to delete your data. It draws on Wispr's privacy page, data controls page, privacy policy (last updated 19 August 2026) and help centre, as of October 2026.

## What leaves your device

- **Audio** of each dictation, streamed as you speak.
- **Context**, when Context Awareness is on. Wispr's help centre lists the name of the app or website, the text before, after and selected around your cursor, on-screen text near the cursor, recipient and participant names, file and variable names in code editors, and the recent messages in a chat. It says the feature works from text and does not take screenshots, and that it skips password fields, financial apps and fields that hold only numbers. Wispr's privacy policy files this under "screen content". It is on by default on Mac, Windows and, for the focused text field, iPhone.
- **Your dictionary and snippets**, which sync between your devices.
- **Meeting audio**, if you use the Notetaker.
- **Account and usage data**: email address, device type, IP address, timestamps, and your Google contacts if you connect a Google account.

## What Wispr keeps

- **Audio** is "deleted as soon as it's transcribed, unless you've turned on Dictation cloud storage". While it is being processed it is held in memory on Wispr's servers.
- **Dictation cloud storage** keeps transcripts, audio and history on Wispr's servers so they sync between your devices. With it off, they are not stored there.
- **Local history** lives on your own computer. You can keep it, have it deleted after 24 hours, or never save it.
- **Context** captured for a dictation is cleared when that dictation ends.
- **Notetaker** transcripts are stored in Wispr's cloud to sync between devices; meeting audio is kept temporarily on the device and sometimes in the cloud, and deleted after processing.

Wispr's pages describe cloud storage and model improvement as settings you control rather than stating what a new personal account starts with, so look at Settings → Data and Privacy on your own install rather than assuming.

## Who else processes it

Wispr uses third-party AI providers for part of the processing. Its privacy policy names them only as "third-party LLM providers and AI service providers". The data controls page says Wispr "always maintains zero data retention agreements with all third-party AI providers"; the privacy policy says data held by those providers is "generally deleted within 30 days". Data is transferred to and processed in the United States. The policy also names Stripe for payments and Google Analytics for the website.

## Is it used to train models?

That is one setting, under Settings → Data and Privacy, which used to be called Privacy Mode and is now phrased as allowing your data to improve the model. When it allows, Wispr says your "audio, transcript, edits" may be used "to evaluate, train, or improve AI models, by Wispr". If you had Privacy Mode on in the past you stay opted out. Growth plans let an administrator control the setting for everyone; on Enterprise plans it is off and cannot be turned on. Meeting audio from the Notetaker is not used for training unless you enable it.

## Security and compliance

Data is encrypted in transit with TLS and at rest on Wispr's servers; stored dictations are protected with AES-256. Wispr is SOC 2 Type 2 compliant, and HIPAA enforcement across an organisation is a feature of the Growth and Enterprise plans.

On a Mac, Wispr Flow needs the Accessibility permission to insert text and to read the context around your cursor; the Microphone permission to hear you; and nothing else for dictation. Wispr's help centre says Screen Recording is not needed for basic dictation. The Notetaker records what your computer plays, which on macOS needs the separate Screen & System Audio Recording permission.

## The settings worth checking

All under Settings → Data and Privacy:

1. **Model improvement.** Turn it off if you do not want your dictations used for training.
2. **Dictation cloud storage.** Leave it off unless you want your history synced between devices. It is the difference between audio deleted on transcription and audio kept.
3. **Local history.** On a shared or managed computer, choose 24 hours or never.
4. **Context Awareness.** Turn it off if you dictate into apps whose contents should not leave the machine. Expect names and formatting to be a little less accurate without it.

## Deleting your data

Deleting your account removes, in Wispr's words, "local and cloud account data — dictionary, Flow Notes, preferences, transcripts, audio and usage history" and revokes integrations. On Mac, Windows and iPhone it is under Settings → Account → Delete account; on desktop you confirm by typing your email address. It cannot be undone. Two warnings from the help centre: it does not cancel an App Store or Google Play subscription, and a subscription billed by Wispr itself is cancelled at once with no refund, so cancel and settle any refund first.

Uninstalling the app does not delete the account or anything on Wispr's servers. The help centre lists the folders a Mac uninstall leaves behind under `~/Library`, if you want them gone too.

Under the GDPR and similar laws you can ask for access, correction, deletion or a copy of your data at support+privacy@wisprflow.ai.

## When cloud dictation is the wrong tool

For most everyday writing, Wispr's arrangement is a reasonable trade: audio deleted after transcription, encryption in transit, a published policy, and controls over the rest. The cases where it does not fit are the ones where the words themselves must not leave your machine: client-confidential or legally privileged material, medical notes outside a HIPAA plan, source code under NDA, or simply an employer whose policy forbids cloud transcription.

For those, use dictation that runs on the device. The dictation built into macOS can process speech on the Mac, and the Keyboard settings show whether it is doing so. Apps that run the speech model locally include our own [JustScribe](/guides/offline-speech-to-text-mac), which is free, open source and has no servers at all, and Superwhisper and MacWhisper, which offer local models alongside cloud ones.

## Sources

Checked in October 2026: Wispr Flow's [privacy page](https://wisprflow.ai/privacy), [data controls](https://wisprflow.ai/data-controls) and [privacy policy](https://wisprflow.ai/privacy-policy); its help centre on [Context Awareness](https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness), [managing your account](https://docs.wisprflow.ai/articles/7339517111-manage-your-flow-account), [uninstalling](https://docs.wisprflow.ai/articles/3884018196-completely-removing-wispr-flow-from-your-device) and [permissions](https://docs.wisprflow.ai/articles/5510622673-re-verify-wispr-flow-permissions-after-updating); and the [Notetaker page](https://wisprflow.ai/notetaker).
