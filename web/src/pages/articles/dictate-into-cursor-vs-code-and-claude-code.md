---
layout: ../../layouts/Page.astro
title: "Dictate Into Cursor, VS Code and Claude Code on a Mac"
description: "How to talk to coding agents instead of typing: the voice modes in Claude Code, Cursor and VS Code, their limits, and dictation that works in all three."
heading: "How to dictate into Cursor, VS Code and Claude Code on a Mac"
updated: "2026-10-14"
faq:
  - q: "Does Claude Code have voice input?"
    a: "Yes. Run /voice in the CLI, then hold Space to speak, or switch to tap mode to toggle recording. It needs a Claude.ai sign-in and a local microphone, and the audio is transcribed on Anthropic's servers. The VS Code extension has the same feature."
  - q: "Can I dictate into the terminal?"
    a: "Not with the voice modes built into Cursor or VS Code, which only fill their own chat boxes. A system-wide dictation app can, because it pastes or types into whatever has focus, including Terminal, iTerm2 and Claude Code running inside them."
  - q: "Should I dictate code itself?"
    a: "Rarely. Dictate what you want in plain language and let the agent write the code. Say file and function names as words; a dictation app with a vocabulary can be taught to spell them, and the agent will usually resolve a near miss."
---

Prompts to a coding agent are prose, and prose is faster spoken than typed. Describing a bug, a refactor or the shape of a feature takes a paragraph; at speaking pace that is twenty seconds, at typing pace a minute or two. Hence the interest in dictating into Claude Code, Cursor and VS Code. There are two ways to do it: the voice modes the tools now ship with, and a dictation app that works everywhere. This page covers both as they stand in October 2026, and where each stops.

## The built-in voice modes

### Claude Code

Claude Code's CLI has dictation built in. Run `/voice` and it is on, in hold mode by default: hold `Space` while the prompt is focused, speak, and release. Your words appear in the prompt as you talk, dimmed until final, and the cursor stays at the end so you can keep typing. `/voice tap` switches to a toggle: tap once to record, tap again to send, with short transcripts left unsent so a stray tap does not fire. `Esc` or `Ctrl` `C` cancels a recording.

Things worth knowing from its documentation:

- Transcription is "tuned for coding vocabulary" and your project and branch names are added as hints, so `regex`, `OAuth` and your repository's name come out right more often than in a general dictation tool.
- It needs a Claude.ai sign-in. With an API key, Bedrock, Vertex or Foundry it is not available. It also needs a local microphone, so it does not work over SSH or in cloud sessions.
- "Voice dictation streams your recorded audio to Anthropic's servers for transcription. Audio is not processed locally."
- Hold mode detects a held key through key-repeat, so there is a brief warm-up; binding a modifier combination such as `meta+k` in `~/.claude/keybindings.json` removes it.
- Twenty dictation languages, set with the same `language` setting as Claude's replies.
- The first run asks macOS for microphone access for your terminal app, not for Claude Code.

The VS Code extension for Claude Code has the same dictation, with the same account requirement, and not in remote sessions.

### Cursor

Cursor's voice input lives in the Agent panel: a microphone icon next to the input, and, by Cursor's own account on its forum, `Control` `M` as a hold-to-talk key. Cursor's prompting guide says to speak naturally, include file and function names, and review the transcription before sending. The transcription happens on Cursor's side. It fills the agent input and nothing else: not the editor, not `Command` `K`, not the integrated terminal.

### VS Code

VS Code's voice support comes from Microsoft's VS Code Speech extension. It is the one option here that runs on the machine: "No internet connection is required, the voice audio data is processed locally on your computer." `Command` `Option` `V` starts dictation in the editor, and `Command` `I` in chat, where holding the key works like a walkie-talkie. It supports 26 languages. It is aimed at the editor and the chat views, and it does not know your project's vocabulary.

## Where they all stop

Each of these works only in its own box. Step outside it, to the terminal where Claude Code is running if you did not use `/voice`, to a commit message, a pull request description, a GitHub issue, a Slack thread or a design document, and you are typing again. For most developers that is where half the prose lives.

Two of the three also send audio to a server, which matters if the prompt describes code under a confidentiality agreement. And none of them lets you carry one vocabulary across every tool.

## System-wide dictation

A dictation app sits in the menu bar and listens for a shortcut. Hold it, speak, release, and the text lands where your cursor is, in any app, because the app inserts it the way a paste or a keystroke would. That covers Claude Code in a terminal, Cursor's agent box and its editor, VS Code, your browser and your chat client with one habit.

Three things to get right for coding use:

1. **Pick a shortcut that is not a typing key.** Claude Code's own voice mode uses `Space`, which is fine inside its prompt. A system-wide app should use modifiers, `Control` `Shift` `Space` or a single modifier held down, so holding it never types.
2. **Teach it your identifiers.** The remaining errors in code dictation are names: `useAuthStore`, `kubectl`, the name of your service. Apps with a vocabulary let you add the spelling and, in some, the way it tends to be misheard. Say identifiers as words ("use auth store") and let the vocabulary or the agent map them.
3. **Mind the terminal.** Terminal's Secure Keyboard Entry and the equivalent in iTerm2 block some apps' shortcuts; turn it off if a shortcut dies only there. A long dictation pasted into Claude Code is shown collapsed as pasted text, but all of it is sent.

**Dictate intent, not syntax.** The agent is better at writing `for` loops than you are at saying them. Describe the behaviour, the constraints and the files involved, and let it produce the code. Keep auto-submit off so you can read the transcript before it goes.

### Which app

- **Wispr Flow** is cloud-based and defaults to the `Fn` key. Its Context Awareness reads the text around your cursor, which helps with names and should be turned off for code that must not leave the machine. It has a help page on using it with Cursor and VS Code.
- **Superwhisper** runs models locally, with cloud options, and its modes can be set per app.
- **JustScribe**, which we make, is free, open source and on-device only. Its vocabulary takes "heard as" forms for identifiers, and its clean-up modes are bound to apps, so a mode for Cursor and the terminal can be told to leave code words alone while a mode for Slack fixes grammar. [How it works.](/)

## A workflow that holds up

Short instructions, hold the key and speak. Long specifications, use a toggle mode, talk through the feature in order, and read it back before pressing Enter. Keep one vocabulary of your project's names in whichever tool you choose. And when the agent misreads a name, correct it once in the vocabulary rather than every time in the prompt.

## Sources

Checked in October 2026: Claude Code's [voice dictation documentation](https://code.claude.com/docs/en/voice-dictation); Cursor's [prompting guide](https://cursor.com/docs/agent/prompting) and its [forum](https://forum.cursor.com/t/microphone-bug-in-agent-window-with-m-hotkey/159723); the [VS Code Speech extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode.vscode-speech); Wispr Flow's help page on [Cursor, VS Code and other IDEs](https://docs.wisprflow.ai/articles/6434410694-use-flow-with-cursor-vs-code-and-other-ides).
