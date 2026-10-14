---
layout: ../../layouts/Page.astro
title: "Parakeet vs Whisper: Which Speech Model for Your Mac?"
description: "NVIDIA's Parakeet and OpenAI's Whisper both run on an Apple silicon Mac. How they differ in speed, accuracy, languages, size and quirks, and which to pick."
heading: "Parakeet vs Whisper: choosing a speech model for a Mac"
updated: "2026-10-14"
faq:
  - q: "Is Parakeet more accurate than Whisper?"
    a: "On English benchmarks, slightly. On the Open ASR Leaderboard, Parakeet TDT 0.6B v2 averages 6.05 percent word error rate and v3 6.34 percent; Whisper Large v3 is usually reported around 7.4 percent. Outside Parakeet's 25 European languages, Whisper is the only one of the two that works at all."
  - q: "Why is Parakeet so much faster than Whisper?"
    a: "Architecture. Parakeet is a transducer that emits text in one pass as audio comes in. Whisper is an encoder-decoder that generates the transcript token by token, and its large model has two and a half times the parameters. On a Mac the difference is the gap between text appearing as you speak and a pause after you stop."
  - q: "Which should I use for dictation?"
    a: "Parakeet v3 if you dictate in one of its 25 languages, which include English, German, French, Spanish, Italian, Portuguese, Polish, Dutch, the Nordic languages, Russian and Ukrainian. Whisper Large v3 if you need a language it lacks, such as Chinese, Japanese, Arabic or Hindi, or for difficult recordings where its size helps."
---

Two open speech-recognition models account for nearly all on-device dictation on Macs today: Whisper, from OpenAI, and Parakeet, from NVIDIA. Apps such as JustScribe, Superwhisper and MacWhisper offer one or both, converted to run on Apple's Neural Engine and GPU. They are built differently, and the difference shows in speed, languages and the kind of mistakes they make. This page explains what each is and how to choose, from the model cards and the Open ASR Leaderboard as of October 2026.

## The two families

**Whisper** was released by OpenAI in September 2022 under the MIT licence: an encoder-decoder transformer trained on 680,000 hours of audio from the web, in about 100 languages, that also translates into English. It comes in sizes from Tiny (39 million parameters) to Large (1.55 billion), the latest Large being v3, plus Turbo, a Large v3 with its decoder cut from 32 layers to 4 that OpenAI describes as "faster transcription speed with a minimal degradation in accuracy". It processes audio in 30-second windows. On the Mac it runs through [WhisperKit](https://github.com/argmaxinc/WhisperKit), Argmax's Core ML port.

**Parakeet** is a family of models from NVIDIA's NeMo team under the CC-BY-4.0 licence. The ones that matter here are Parakeet TDT 0.6B v2 (English, May 2025) and v3 (25 European languages, August 2025). TDT stands for Token-and-Duration Transducer: a FastConformer encoder feeding a transducer decoder that predicts each token and how long it lasts, so it emits text in a single pass as audio arrives. Both are 600 million parameters, add punctuation and capitalisation themselves, give word-level timestamps, and take up to 24 minutes of audio in one go. On the Mac they run through [FluidAudio](https://github.com/FluidInference/FluidAudio), a Core ML port.

## Accuracy

The common yardstick is the [Open ASR Leaderboard](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard), an average word error rate over eight English test sets.

| Model | Parameters | Languages | Average WER, English |
|---|---|---|---|
| Parakeet TDT 0.6B v2 | 0.6 B | English | 6.05 % |
| Parakeet TDT 0.6B v3 | 0.6 B | 25 European | 6.34 % |
| Whisper Large v3 | 1.55 B | ~100 | about 7.4 % |
| Whisper Large v3 Turbo | 0.81 B | ~100 | higher than Large v3 |

So in English, the smaller Parakeet is slightly more accurate than the largest Whisper. On the FLEURS multilingual benchmark Parakeet v3 averages 11.97 percent across its 25 languages; Whisper's accuracy varies widely by language, excellent in the big European ones and much worse in low-resource ones. Numbers like these are averages over read speech and podcasts. Dictation is cleaner audio than most test sets, so both models do better than their leaderboard figure, and the remaining errors are mostly names and jargon rather than ordinary words.

## Speed

Parakeet's single-pass design is why dictation apps use it for the live text that appears while you talk. On NVIDIA's hardware it reports a real-time factor in the thousands; on an M-series Mac it transcribes a few seconds of speech in a fraction of a second. Whisper generates its output token by token, and Large v3 on a Mac takes long enough that apps run it only after you stop speaking. Whisper Small and Base are fast but trade away accuracy; Turbo sits between.

## Languages

Whisper's breadth is its trump card: about 100 languages, including Chinese, Japanese, Korean, Arabic, Hindi, Turkish, Vietnamese, Thai and Hebrew, with the usual caveat that quality tracks how much training data a language had. Parakeet v3 covers 25: Bulgarian, Croatian, Czech, Danish, Dutch, English, Estonian, Finnish, French, German, Greek, Hungarian, Italian, Latvian, Lithuanian, Maltese, Polish, Portuguese, Romanian, Russian, Slovak, Slovenian, Spanish, Swedish and Ukrainian, detecting which one you are speaking on its own. If your language is not on that list, the choice is made for you.

## Quirks

**Whisper invents text in silence.** Fed background noise or a pause, it sometimes produces a plausible phrase that nobody said, or repeats a line. Apps mitigate this by not sending near-silent audio and by padding very short clips: Whisper decodes nothing at all from a second or less of audio, so a short "yes" needs a little silence appended before it is recognised.

**Whisper can be prompted.** Its decoder accepts a text prefix, which apps use to pass your vocabulary, up to a couple of hundred tokens, so unusual names come out right more often. Parakeet has no equivalent; vocabulary has to be fixed after transcription.

**Parakeet rejects very short audio.** Under about a third of a second it returns nothing, so apps pad that too. It does not hallucinate in the Whisper way, but it can drop a word at the edge of a chunk, which is why file-transcription pipelines cut audio at quiet points rather than at fixed intervals.

**Parakeet needs no post-processing for punctuation and case.** Whisper's output is also punctuated, but the smaller Whisper models are less reliable about it.

## Size and memory

As downloaded by JustScribe, with the memory each takes while loaded:

| Model | Download | Memory while loaded |
|---|---|---|
| Parakeet v3 | ~480 MB | ~600 MB |
| Parakeet English (v2) | ~460 MB | ~500 MB |
| Whisper Tiny | ~75 MB | ~200 MB |
| Whisper Base | ~142 MB | ~350 MB |
| Whisper Small | ~466 MB | ~900 MB |
| Whisper Medium | ~1.5 GB | ~2.6 GB |
| Whisper Large v3 | ~3 GB | ~5.2 GB |

Other apps ship slightly different conversions and quantisations, so their figures differ by a little.

## Which to pick

- **Dictation in a language Parakeet covers:** Parakeet v3. Fast enough for live text, more accurate than Whisper in English, and small.
- **English only, and every fraction counts:** Parakeet English (v2), marginally more accurate than v3 in English.
- **A language Parakeet lacks:** Whisper Large v3, or Medium if memory is tight. Below Small, the multilingual Whisper models make too many mistakes for serious use.
- **Difficult recordings** such as a noisy meeting file: Whisper Large v3 is worth its slowness, and its prompting lets you feed it the names that will come up.
- **A Mac with 8 GB of memory:** Parakeet v3, or Whisper Small. Large v3 wants more than five gigabytes while loaded.

The safest advice is to install both. On JustScribe they are a click apart in Settings, with Parakeet v3 recommended by default and Whisper there for the languages and recordings it is better at; see [offline speech to text on Mac](/guides/offline-speech-to-text-mac). Superwhisper offers every Whisper model free and Parakeet on its Pro tier.

## Sources

Checked in October 2026: the model cards for [Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) and [v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2); OpenAI's [Whisper repository](https://github.com/openai/whisper) and [paper](https://arxiv.org/abs/2212.04356); the [Open ASR Leaderboard](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard); [WhisperKit](https://github.com/argmaxinc/WhisperKit) and [FluidAudio](https://github.com/FluidInference/FluidAudio).
