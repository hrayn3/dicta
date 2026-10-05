# Dicta

Tiny, fully offline push-to-talk dictation for macOS. Built for a lawyer with
a broken hand.

Tap a shortcut, speak, tap again — the transcript is pasted wherever your
cursor is. Everything runs on-device (NVIDIA Parakeet TDT v3 on the Apple
Neural Engine, via [FluidAudio](https://github.com/FluidInference/FluidAudio)).
No cloud, no accounts, no analytics. Audio is never written to disk.

## Install

Needs an Apple Silicon Mac on macOS 14+ with the full Xcode app installed
(tested with Xcode 26).

```sh
git clone https://github.com/hrayn3/dicta.git
cd dicta
./scripts/make-app.sh --install
```

That checks your setup (and tells you how to fix anything missing), builds
the app, installs it to `/Applications` and launches it. Dicta has no window:
look for its icon in the menu bar, and allow Accessibility when macOS asks.

**Or let a coding agent do it.** Paste this into Claude Code, Codex or
similar:

> Install Dicta from https://github.com/hrayn3/dicta by following its
> INSTALL.md. Stop and ask me for any step marked (human).

See [INSTALL.md](INSTALL.md) for the full steps and troubleshooting.

## Use

- **Tap ⌃⌥Space** (configurable) to start recording; the menu bar icon becomes
  a record dot. Speak. Tap again to finish — text appears at your cursor.
  The whole take is transcribed in one pass when you stop (about 0.2 s for
  30 s of speech), and your previous clipboard comes back afterwards.
- **Esc** while recording cancels it (nothing is pasted). The Esc press is
  not passed on to the app you're typing in.
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
./scripts/make-app.sh            # → dist/Dicta.app
./scripts/make-app.sh --install  # also copy to /Applications and launch
```

The bundle is signed with `$CODESIGN_ID` if set, else a local "Dicta Dev
Signing" certificate if you have one, else ad-hoc. With ad-hoc signing,
macOS treats each build as a new app, so the script clears the old
Accessibility grant and you allow it again after each rebuild.

## License

Dicta is available under the [MIT License](LICENSE). See
[Third-party notices](THIRD_PARTY_NOTICES.md) for FluidAudio,
KeyboardShortcuts, and NVIDIA Parakeet licensing and attribution.

## Permissions

- **Microphone** — prompted on first recording.
- **Accessibility** (System Settings → Privacy & Security → Accessibility) —
  needed to paste at the cursor. Without it, transcripts still land on the
  clipboard and in history.
