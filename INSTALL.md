# Installing Dicta

Written so either a person or a coding agent (Claude Code, Codex, …) can
follow it top to bottom. Steps marked **(human)** need the person at the Mac:
an agent should stop and ask them, not try to work around it.

## 1. Check the Mac

```sh
uname -m                     # must print arm64 (Apple Silicon)
sw_vers -productVersion      # must be 14 or newer
xcode-select -p              # must point inside Xcode.app, not CommandLineTools
xcodebuild -license check    # must exit 0
```

If a check fails:

| Problem | Fix |
| --- | --- |
| Not `arm64` | Dicta can't run on this Mac. |
| No Xcode | **(human)** Install Xcode from the App Store (~10 GB; tested with Xcode 26), open it once. The Command Line Tools alone fail with `plugin for module 'PreviewsMacros' not found`. |
| Points at `CommandLineTools` | **(human)** `sudo xcode-select -s /Applications/Xcode.app` |
| Licence not accepted | **(human)** `sudo xcodebuild -license accept` |

`scripts/make-app.sh` runs these checks itself and prints the fix if one
fails.

## 2. Build

```sh
git clone https://github.com/hrayn3/dicta.git
cd dicta
./scripts/make-app.sh
```

The first build fetches dependencies and takes about 3–5 minutes. It ends with
`Built dist/Dicta.app`.

## 3. Verify transcription (optional, recommended for agents)

This loads the speech model and transcribes a clip without needing the
microphone or any permissions. On a new Mac the first run downloads the model
(~600 MB from Hugging Face), so allow several minutes.

```sh
say -o /tmp/dicta-check.aiff "Please send the signed contract before Friday."
dist/Dicta.app/Contents/MacOS/Dicta --selftest /tmp/dicta-check.aiff
```

Expect a line like `selftest raw: Please send the signed contract before
Friday.` and exit code 0.

## 4. Install and launch

```sh
./scripts/make-app.sh --install
```

This rebuilds, copies the app to `/Applications/Dicta.app` (quitting any
running copy first) and launches it. Keeping it in `/Applications` means
"Launch at login" keeps pointing at the right place.

## 5. Grant permissions **(human)**

Dicta has **no window**. It lives in the menu bar (top right). On a MacBook
with a notch, a crowded menu bar can hide it behind the notch; quit a few
menu bar apps if you can't see it.

1. **Accessibility**: macOS asks on first launch. Turn Dicta on in System
   Settings → Privacy & Security → Accessibility. This is what lets it paste
   at your cursor. Without it, transcripts only go to the clipboard.
2. **Microphone**: macOS asks the first time you dictate.

## 6. Try it **(human)**

Click into any text field, tap **⌃⌥Space**, speak, tap **⌃⌥Space** again.

If nothing happens, open the menu bar icon: it shows whether the model is
still downloading, whether Accessibility is missing, and lets you change the
shortcut. You can also switch on "Use 🌐 Fn key as shortcut". For that, set
System Settings → Keyboard → "Press 🌐 key to" → "Do Nothing".

## Troubleshooting

- **⌃⌥Space switches keyboard layout instead.** That's macOS's "Select next
  source in Input menu" shortcut, active when you have two or more input
  sources. Change Dicta's shortcut in its menu, or turn that one off in System
  Settings → Keyboard → Keyboard Shortcuts → Input Sources.
- **Dicta is switched on under Accessibility but won't paste.** Each build is
  signed with a throwaway (ad-hoc) signature, so a grant from an older build
  doesn't carry over even though the switch still looks on.
  `make-app.sh` clears the stale entry for you. If it still happens, run
  `tccutil reset Accessibility com.hughrayner.dicta`, relaunch Dicta and allow
  it again.
- **"Dicta can't be opened" / "unidentified developer"** only happens when
  the app was copied from another Mac. Open it once, then go to System
  Settings → Privacy & Security and click **Open Anyway**. (On macOS 15 and
  later, right-click → Open no longer skips this.) Building it yourself avoids
  the prompt.
- **Stuck on "Downloading speech model…"**: the first launch needs internet
  access to huggingface.co. After that, Dicta never uses the network.
