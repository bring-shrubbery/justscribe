---
layout: ../../layouts/Page.astro
title: "Wispr Flow vs Apple Dictation on a Mac: What Changes"
description: "Apple Dictation is free and built in; Wispr Flow costs money and uses the cloud. What each does, and how they differ in editing, privacy and languages."
heading: "Wispr Flow vs the dictation built into macOS"
updated: "2026-10-14"
faq:
  - q: "Is Wispr Flow better than Apple Dictation?"
    a: "It produces tidier text: filler words removed, self-corrections applied, punctuation and tone handled for you, and names spelled from a dictionary. Apple's Dictation writes down what you said, punctuates it in supported languages, and that is all. Whether tidier text is worth $15 a month and a round trip to Wispr's servers depends on how much you dictate and what."
  - q: "Does Apple Dictation work offline?"
    a: "On an Apple silicon Mac it can process speech on the device once the language's model is downloaded, and Keyboard settings show whether it is doing so. Wispr Flow never works offline."
  - q: "Can I use Wispr Flow and Apple Dictation at the same time?"
    a: "Yes. Both can be on at once with different shortcuts. Wispr Flow uses the Fn key by default, and Apple's Dictation can be set to a double press of the Globe key, the Control key or a Command key, or turned off."
---

Every Mac can already take dictation. Turn it on under System Settings → Keyboard, press the shortcut, and talk. Wispr Flow asks you to install an app, create an account and, beyond a weekly allowance, pay. The question is what you get for that. This page lays the two side by side from Apple's user guide and Wispr's documentation as of October 2026.

## Side by side

| | Apple Dictation | Wispr Flow |
|---|---|---|
| Price | Included with macOS | Free for 2,000 words a week on desktop; Pro $15 a month, or $144 a year |
| Setup | Switch it on in Keyboard settings | Download, account, Microphone and Accessibility permissions |
| Start and stop | Press the shortcut; it stops when you press again or after 30 seconds of silence; no limit on length | Hold `Fn` while you speak and release; or hands-free for up to 20 minutes |
| Where speech is processed | On the Mac for general dictation on Apple silicon, once the language's model is downloaded; Keyboard settings say whether it is on-device | Always on Wispr's servers |
| Works offline | Yes, when processed on-device | No |
| What you get back | What you said, with automatic punctuation in supported languages; spoken punctuation, "new paragraph" and emoji by name | What you meant: filler and false starts removed, mid-sentence corrections applied, punctuation, lists, tone chosen per app |
| Names and jargon | No personal dictionary | A dictionary learned from your corrections; snippets |
| Editing by voice | Not in Dictation; Voice Control, a separate accessibility feature, does it | Command Mode rewrites selected text from an instruction (paid, experimental) |
| Languages | Many; on-device processing, punctuation and emoji each have their own list | More than 100, switched automatically mid-sentence |
| Other devices | iPhone and iPad have the same dictation; nothing on Windows | Windows, iPhone, Android |
| Your data | Processed on the device, or by Apple when not | Streamed to Wispr; audio deleted after transcription unless cloud storage is on; third-party AI providers under zero-retention agreements |

## What Apple's Dictation does well

It is already there, needs no permissions beyond the microphone, works in any text field, and costs nothing. On an Apple silicon Mac it can do the recognition on the machine, which makes it private and usable with no connection. It adds commas, full stops and question marks on its own in supported languages, it understands "new paragraph" and "full stop" when you prefer to say them, and it will insert an emoji if you name one. For a sentence here and a message there, it is enough, and many people never need more.

## Where it falls short

Dictation writes down speech, and speech is messy. Say "send it Tuesday, no, Wednesday" and that is what you get, with the "no" in the middle. There is no dictionary, so an unusual name is wrong every time, and no notion of the app you are in, so a Slack message and a formal email come out in the same register. It stops after 30 seconds of silence, which catches people who pause to think. And there is no way to correct by voice without turning on Voice Control, a much larger accessibility system that takes over more than dictation.

## What Wispr Flow adds

Wispr Flow's whole pitch is the second step. After recognition it edits: removes the filler, applies your corrections, punctuates, formats lists, matches a tone to the app, and reads the text around the cursor so that the Sam you are replying to is spelled like the Sam on screen. A dictionary carries your names and jargon across every device, and the result is the same on a Windows laptop and a phone as on the Mac. For someone who dictates paragraphs rather than sentences, the time saved on cleaning up is the product.

## What you give up

- **The machine boundary.** Everything you dictate goes to Wispr's servers; that is how it works, not a setting. For most writing it is fine. For anything that must not leave the Mac, it is disqualifying, and Apple's on-device option is the safer tool. See [Is Wispr Flow private?](/articles/wispr-flow-privacy).
- **Offline use.** Wispr Flow does nothing without a connection. See [Does Wispr Flow work offline?](/articles/does-wispr-flow-work-offline)
- **Money, eventually.** The free plan's 2,000 words a week covers light use. Past it, Pro is $15 a month. See [Wispr Flow pricing](/articles/wispr-flow-pricing).
- **An account and two permissions.** Wispr Flow needs Accessibility access to insert text and read context. Apple's Dictation is part of the system and needs neither.

## Running both

There is no reason to choose before trying. Keep Apple's Dictation on and install Wispr Flow; they coexist as long as their shortcuts differ. Wispr Flow takes the `Fn` key by default. Apple's Dictation shortcut is set under Keyboard → Dictation, and can be a double press of `Fn`, `Control` or a `Command` key, or anything you define. Pick one that is not `Fn` so a single press does not confuse the two, and check the "Press Globe key to" setting in the same place; [the Fn key on a Mac](/articles/mac-fn-key) explains what that setting does.

Then dictate the same paragraph with each, in the app you write in most, and count the corrections. The one that needs fewer on your voice and your vocabulary is the right one for you.

## A middle path

If what tempts you about Wispr Flow is the clean-up, and what holds you back is the cloud, that combination exists on the Mac: apps that run the speech model and the clean-up model on the machine. Our own [JustScribe](/vs-apple-dictation) is one, free and open source; Superwhisper is another, with local and cloud options.

## Sources

Checked in October 2026: Apple's [Dictate messages and documents on Mac](https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac) and [Commands for dictating text on Mac](https://support.apple.com/guide/mac-help/commands-for-dictating-text-on-mac-mh40695/mac); Wispr Flow's [home page](https://wisprflow.ai), [pricing](https://wisprflow.ai/pricing) and [data controls](https://wisprflow.ai/data-controls), and its help centre on [starting a dictation](https://docs.wisprflow.ai/articles/6409258247-starting-your-first-dictation) and [Context Awareness](https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness).
