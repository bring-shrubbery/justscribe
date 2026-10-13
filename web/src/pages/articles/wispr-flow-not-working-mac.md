---
layout: ../../layouts/Page.astro
title: "Wispr Flow Not Working on Mac? A Fix-It Checklist"
description: "Wispr Flow stopped working on your Mac? The causes by symptom: the Fn key, Accessibility after an update, Secure Keyboard Entry, the microphone, the network."
heading: "Wispr Flow not working on a Mac: a checklist by symptom"
updated: "2026-10-13"
faq:
  - q: "Why did Wispr Flow stop working after a macOS update?"
    a: "macOS updates can reset the Accessibility and Microphone permissions. Open System Settings, Privacy & Security, switch Wispr Flow off and on again under Microphone, make sure it is on under Accessibility, and restart Flow. Wispr's help centre recommends re-verifying both after any system or app update."
  - q: "Why does Fn + Space stop working in Terminal while holding Fn still works?"
    a: "Terminal's Secure Keyboard Entry, and the equivalent in iTerm2 and password managers, blocks other apps from seeing keystrokes. Turn it off in the Terminal menu, close the password manager's window, or click into a field that is not a password field, and the hands-free shortcut comes back."
  - q: "Does Wispr Flow work without internet?"
    a: "No. Transcription runs on Wispr's servers. A no-internet notice, a VPN that is still connecting, a firewall, or hotel Wi-Fi waiting for a login all stop it."
---

Wispr Flow has a few moving parts on a Mac: a shortcut key, two system permissions, a microphone and a connection to Wispr's servers. When it stops working, the symptom tells you which one. Find yours below. Each fix is from Wispr's help centre as of October 2026, with the links at the end.

## Nothing happens when you hold the shortcut

**Which key is it?** The default push-to-talk key is `Fn`. On Macs without an Apple Fn key, including many external keyboards, Flow's onboarding sets `Control` `Option` instead, and `Control` `Option` `Space` for hands-free mode. Check what Flow thinks the shortcut is under Settings → General → Shortcuts.

**Is macOS using the key?** System Settings → Keyboard has a setting for what pressing the `Fn` or globe key does (show emoji, change input source, start Apple's dictation, or nothing). Flow says assigning `Fn` prevents its usual system action, but if a tap of the key opens the emoji picker or Apple's own dictation, set it to Do Nothing and try again.

**Does another app own the shortcut?** Change Flow's shortcut to something distinctive, or change the other app's. Flow accepts combinations of `Control`, `Command`, `Option`, `Shift` and `Fn`, and some mouse buttons; it does not accept a bare letter or number, nor `Command` `Space` and a few other system combinations.

**Is Caps Lock the shortcut?** Caps Lock needs the Input Monitoring permission as well: System Settings → Privacy & Security → Input Monitoring.

## The waveform appears, but no text lands

Flow heard you, sent the audio, got the text back, and had nowhere to put it. That is the **Accessibility** permission.

1. Open System Settings → Privacy & Security → Accessibility.
2. If Wispr Flow is listed and off, turn it on. If it is listed and on, turn it off and on again.
3. If it is not listed at all, reinstall Flow. The app must be called `Wispr Flow.app` and sit directly in `/Applications` or `~/Applications`; a copy left in Downloads or renamed will not be granted the permission reliably.
4. Restart Flow.

macOS and app updates can reset this permission silently, which is why Flow most often "stops working" the day after an update. Wispr's help centre recommends re-verifying Microphone and Accessibility after any update.

If text lands in the wrong place, check which field had focus when you released the key: Flow inserts into the field that is focused at the moment the text arrives.

## Hands-free or Escape stops working, but holding the key still works

This is **Secure Keyboard Entry**, a macOS feature that stops apps seeing keystrokes while it is on. Wispr describes the symptom exactly: "Fn+Space (hands-free) or Escape (cancel) stops responding while Fn hold-to-talk and typing still work."

Common sources, and the fix for each:

- **Terminal:** uncheck Terminal → Secure Keyboard Entry in the menu bar.
- **iTerm2:** it can keep Secure Input on in the background, so switching windows may not release it; quit it with `Command` `Q`.
- **Password managers** such as 1Password: close their windows.
- **Browsers:** a focused password field turns it on; click into another field or switch apps.

If the block stays after the offending app is gone, lock the screen with `Control` `Command` `Q`, unlock, and if needed log out and back in. Once `Fn` `Space` starts a hands-free dictation again, nothing in Flow needs restarting.

## Flow hears nothing, or reports a microphone problem

1. **Permission:** System Settings → Privacy & Security → Microphone must include Wispr Flow, switched on. Toggling it off and on fixes a stale grant.
2. **The right input:** Flow Settings → General → Microphone → Change, and pick the microphone by name. Inputs that are listed but greyed out are not available right now.
3. **Bluetooth:** compare the built-in or a wired microphone with the headset. A wireless receiver can deliver silence when its transmitter is out of range or asleep.
4. **Level:** System Settings → Sound → Input; raise a low input level.
5. **Another app holding the microphone:** close other apps that use it. Flow does not tell you which one has it.
6. **Hardware:** a mute switch on the headset or keyboard, or a MacBook with its lid closed, which disables the built-in microphone.

## "Is your internet connected?" or "No internet connection"

Wispr Flow transcribes on its servers and cannot work offline. Check the connection, and remember the cases that look connected but are not: hotel or airport Wi-Fi waiting for you to accept its terms, a VPN still connecting, or a workplace firewall that blocks Wispr. If the message appeared mid-dictation, reconnect and retry; Wispr says the audio is retained for that. More in [Does Wispr Flow work offline?](/articles/does-wispr-flow-work-offline)

## Dictation is blocked, or stops on its own

- **A card says you have reached your limit.** The free plan allows 2,000 dictated words a week on desktop, and the block lasts until the count resets on Sunday at 12 a.m. Pacific time. Restarting the app does not reset it. See [Wispr Flow pricing](/articles/wispr-flow-pricing).
- **A hands-free session ended by itself.** Hands-free mode records for up to 20 minutes, and ends sooner when no audio is detected or microphone access fails.
- **"Flow is having trouble loading or starting."** Choose Restart Flow. If it repeats, use Contact us in the app.

## It will not install or open

Wispr ships separate builds for Apple silicon and Intel Macs, with no universal one; download the build for your chip from wisprflow.ai. Flow needs macOS 12 Monterey or later, about 500 MB of disk space, and Wispr recommends 8 GB of memory.

## A clean reinstall

When nothing above helps, remove Flow completely before installing it again. Quit the app, move it from Applications to the Trash, and delete what the help centre lists:

- `~/Library/Application Support/Wispr Flow` and `~/Library/Application Support/Flow`
- `~/Library/Logs/Wispr Flow`
- `~/Library/Preferences/com.wispr.flowapp.plist`, `com.electron.wispr-flow.plist` and `com.electron.wispr-flow.accessibility-mac-app.plist`
- `~/Library/Saved Application State/com.wispr.flowapp.savedState`
- `~/Library/HTTPStorages/com.wispr.flowapp`
- `~/Library/Caches/com.wispr.flowapp` and `com.electron.wispr-flow`

Then, in System Settings → Privacy & Security, remove the entries for Wispr Flow and Wispr Flow Helper under Microphone, Accessibility and Input Monitoring, so the fresh install asks for them again. Reinstalling does not touch your account, dictionary or subscription; those live on Wispr's servers.

## Still stuck

Use Contact us inside the app, which attaches the logs Wispr's support needs, or browse the [help centre](https://docs.wisprflow.ai).

## Sources

Checked in October 2026, all from Wispr Flow's help centre: [starting your first dictation](https://docs.wisprflow.ai/articles/6409258247-starting-your-first-dictation), [keyboard and mouse shortcuts](https://docs.wisprflow.ai/articles/2612050838-supported-unsupported-keyboard-hotkey-shortcuts), [installing on a Mac](https://docs.wisprflow.ai/articles/7682075140-how-to-install-wispr-flow-on-mac), [re-verifying permissions after an update](https://docs.wisprflow.ai/articles/5510622673-re-verify-wispr-flow-permissions-after-updating), [shortcuts blocked by Secure Keyboard Entry](https://docs.wisprflow.ai/articles/8841649969-fix-flow-shortcuts-blocked-by-macos-secure-keyboard-entry-secure-event-input), [a silent or unavailable microphone](https://docs.wisprflow.ai/articles/4351452717-troubleshooting-mic-issues), [startup and transcription errors](https://docs.wisprflow.ai/articles/3155947051-troubleshooting-guide-for-no-model-available-error), [hands-free mode](https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free), [the free tier's weekly cap](https://docs.wisprflow.ai/articles/4760791189-free-tier-weekly-word-cap-and-bonus-words-remove-desktop-trial-experiment), [system requirements](https://docs.wisprflow.ai/articles/1036674442-supported-devices-and-system-requirements) and [uninstalling](https://docs.wisprflow.ai/articles/3884018196-completely-removing-wispr-flow-from-your-device).
