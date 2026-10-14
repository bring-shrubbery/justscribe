---
layout: ../../layouts/Page.astro
title: "Mac Fn Key: What It Does and How to Use It for Dictation"
description: "What the Fn or Globe key does on a Mac, the setting behind a single press, every Fn shortcut, and how to give the key to a dictation app cleanly."
heading: "The Fn (Globe) key on a Mac: what it does, and how to use it for dictation"
updated: "2026-10-14"
faq:
  - q: "Why does pressing Fn open the emoji picker, or switch my keyboard language?"
    a: "Because of the setting under System Settings → Keyboard called 'Press 🌐 key to' (or 'Press fn key to' on older keyboards). It can show Emoji & Symbols, change the input source, start Dictation, or do nothing. Set it to Do Nothing if you keep hitting it by accident or want the key for an app."
  - q: "Can I make Fn a push-to-talk key for dictation?"
    a: "Several dictation apps use it that way by default, Wispr Flow among them. Set 'Press 🌐 key to' to Do Nothing first, so a press does not also open something, and give Apple's own Dictation a different shortcut. Apps that only accept Control, Option, Shift and Command as modifiers cannot bind Fn directly; a remapping tool such as Karabiner-Elements can turn Fn into one of those."
  - q: "My external keyboard has no Fn key. What now?"
    a: "Use a different shortcut. Wispr Flow switches to Control + Option on Macs without an Apple Fn key, and most apps let you choose any modifier combination. Or remap Caps Lock to Fn with Karabiner-Elements."
---

The key in the bottom-left corner of a Mac keyboard is the odd one out. It is labelled `fn`, or since 2020 with a globe, and it is neither a letter nor a proper modifier. For years it only turned the brightness keys back into F1 to F12. Then macOS started giving it jobs of its own, and dictation apps discovered it was the one key nobody was using. This page explains what it does, how to control it, and how to hand it to a dictation app cleanly.

## One key, two names

Keyboards made before 2020 have `fn`. The Magic Keyboard that shipped with the M1 Macs, and every MacBook since, have a globe icon on the same key, with `fn` printed under it in small type. They are the same key and macOS treats them the same, with one practical difference: the Globe key's single-press behaviour is set up out of the box, while on older keyboards it did nothing on its own.

Many third-party and Windows keyboards have no equivalent. Their `Fn` key, if present, is handled inside the keyboard and never reaches macOS, which is why a dictation app cannot see it.

## What a single press does

System Settings → Keyboard has a pop-up called **Press 🌐 key to** (or **Press fn key to**). Its options:

- **Change Input Source.** Cycles through your keyboard layouts and languages. This is the default when you have more than one input source.
- **Show Emoji & Symbols.** Opens the character viewer. This is the default with one input source, and the reason a stray press pops up emoji.
- **Start Dictation.** Pressed twice, it starts Apple's Dictation. Apple's guide notes that choosing a Dictation shortcut can change this setting on its own.
- **Do Nothing.** A single press does nothing at all.

Whatever you choose, holding the key with another still works as described below.

## What it does held with other keys

- **The function row.** With the default setting, F1 to F12 control brightness, Mission Control, media and volume, and holding `Fn` turns them into plain F-keys. "Use F1, F2, etc. keys as standard function keys" in Keyboard Shortcuts → Function Keys flips that around.
- **Arrows and Delete.** `Fn` with the arrow keys gives Home, End, Page Up and Page Down; `Fn` `Delete` deletes forward.
- **Letters.** `Fn` `E` opens Emoji & Symbols, `Fn` `C` Control Center, `Fn` `N` Notification Center, `Fn` `Q` a Quick Note, `Fn` `F` full screen for the current window, `Fn` `H` shows the desktop, `Fn` `A` moves keyboard focus to the Dock, and `Fn` `D` starts or stops Dictation.

These letter shortcuts are why holding `Fn` for a dictation app is safe in practice: you are holding it and talking, not typing.

## Why dictation apps want it

A push-to-talk key has to be comfortable to hold for ten seconds and must never type anything. `Fn` sits under the little finger, is otherwise idle, and holding it does nothing visible. Wispr Flow and several other apps make it their default, and Apple's own Dictation starts on a double press of it. The problem is that macOS already has plans for the same key, so two things can happen on one press.

## Giving the key to a dictation app

1. **Set "Press 🌐 key to" to Do Nothing.** Otherwise a short press opens emoji or switches your keyboard layout every time you tap it by mistake.
2. **Move Apple's Dictation shortcut.** Under Keyboard → Dictation, set the shortcut to a double press of `Control` or a `Command` key, or turn Dictation off if you will not use it. Two dictation systems on one key is a bad time.
3. **Grant what the app asks for.** Watching for `Fn` needs an event monitor, so some apps ask for Input Monitoring in Privacy & Security in addition to Accessibility and the microphone. Caps Lock as a shortcut always needs it.
4. **Turn off Secure Keyboard Entry** in Terminal if the shortcut dies there; it blocks apps from seeing keystrokes while on.

## When the app cannot bind Fn

`Fn` is not a modifier in the sense the system's hotkey API understands; the real modifiers are `Control`, `Option`, `Shift` and `Command`. Apps that register their shortcuts that way, our own JustScribe among them, accept any combination of those four, including one held alone, but not `Fn`. If you want the physical key under your little finger anyway, remap it with [Karabiner-Elements](https://karabiner-elements.pqrs.org), the free open-source remapper: map `fn` to a key you never use, such as the right `Command` or `F18`, and give that to the app. Karabiner's "fn" modifier handling also lets a keyboard without the key get one by turning Caps Lock into it.

## The other candidates

If `Fn` is spoken for, the common alternatives are `Option` `Space` (Superwhisper's default), `Control` `Shift` `Space` (JustScribe's default), a single modifier held alone such as the right `Command` key, or Caps Lock, which most apps support and which is otherwise the most useless key on the board. Whichever you choose, the test is the same: holding it for as long as a sentence takes should type nothing and open nothing.

## Sources

Checked in October 2026: Apple's [Mac keyboard shortcuts](https://support.apple.com/en-us/102650) and [Dictate messages and documents on Mac](https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac); Wispr Flow's help centre on [starting your first dictation](https://docs.wisprflow.ai/articles/6409258247-starting-your-first-dictation) and [keyboard shortcuts](https://docs.wisprflow.ai/articles/2612050838-supported-unsupported-keyboard-hotkey-shortcuts); MacMost's [The Mac Fn (Globe) Key: Everything It Can Do](https://macmost.com/the-mac-fn-globe-key-everything-it-can-do.html).
