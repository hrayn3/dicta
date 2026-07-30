# Dicta

Tiny, fully offline push-to-talk dictation for macOS. Built for a lawyer with
a broken hand.

Tap a shortcut, speak, tap again — the transcript is pasted wherever your
cursor is. Everything runs on-device (NVIDIA Parakeet TDT v3 on the Apple
Neural Engine, via [FluidAudio](https://github.com/FluidInference/FluidAudio)).
No cloud, no accounts, no analytics. Audio is never written to disk.

## Use

- **Tap ⌃⌥Space** (configurable) to start recording; the menu bar icon becomes
  a record dot. Speak. Tap again to finish — text appears at your cursor.
  Transcription runs *while* you speak, so the result is near-instant.
- **Esc** while recording cancels it (nothing is pasted).
- The menu bar dropdown has your recent transcripts — click one to copy it.
- If a recording is left running with no speech for 5 minutes it stops itself.

## Legal vocabulary / corrections

Edit `~/.dicta-replacements.txt` (menu → "Edit replacements…"):

```
# what the model hears -> what you meant
estopple -> estoppel
mareva injunction -> Mareva injunction
```

Case-insensitive, whole-word, applied after transcription and before pasting.

## Privacy notes

- History lives in `~/Library/Application Support/Dicta/history.jsonl` as
  plain text. Turn off "Keep history" in the menu (or Clear) if you're
  dictating anything that shouldn't sit on disk.
- The speech model (~600 MB) is downloaded from Hugging Face on first launch
  and cached in `~/Library/Application Support/FluidAudio/`. After that the
  app never touches the network.

## Build

```
./scripts/make-app.sh        # → dist/Dicta.app
```

Requires Xcode 26 / Swift 6 and an Apple Silicon Mac (macOS 14+). The bundle
is ad-hoc signed: on a Mac other than the build machine, first launch is
right-click → Open.

## Permissions

- **Microphone** — prompted on first recording.
- **Accessibility** (System Settings → Privacy & Security → Accessibility) —
  needed to paste at the cursor. Without it, transcripts still land on the
  clipboard and in history.
