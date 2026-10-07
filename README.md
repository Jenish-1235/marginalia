# Marginalia

A reading, annotating and learning app for iPad — books, papers and web articles in one library,
Apple Pencil-first annotation, and a notebook that turns highlights into knowledge.
See [`docs/PLAN.md`](docs/PLAN.md) for the full plan and milestones.

## Run it

Requirements: Xcode 27+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate          # creates Marginalia.xcodeproj (not checked in)
open Marginalia.xcodeproj
```

### On your iPad
1. Create `Config/Local.xcconfig` with your team id (Xcode → Settings → Accounts):
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   ```
2. Plug in the iPad, enable Developer Mode (Settings → Privacy & Security), pick it as the run
   destination and press ⌘R.

With a free Apple ID the install expires after 7 days; a paid developer account makes it last a year.

### Tests
```sh
xcodebuild -project Marginalia.xcodeproj -scheme Marginalia \
  -destination 'platform=iOS Simulator,name=iPad (A16)' test
```
UI tests write screenshots when run with `TEST_RUNNER_SHOTS_DIR=<dir>`; the annotation flow needs
`TEST_RUNNER_SAMPLES_DIR=<folder of PDFs>` and the capture flow needs network access.

## Using it

| Do this | Get this |
|---|---|
| Write with Apple Pencil | Ink (fingers always scroll — toggle ✋ in the tool rail to draw with a finger) |
| Smart Highlighter tool, stroke across text | A real text highlight, snapped to whole words |
| Long-press text with a finger, drag to extend | Selection → Highlight · Underline · Note · Question · More |
| Tap a mark | Edit note, change style, mark as question / look-up, copy, delete |
| Two-finger tap / three-finger tap | Undo / redo |
| Notebook button | All marks in reading order + your notes; export Markdown |
| + → Save Web Page… | Browser; log in if needed, then **Save PDF** (clean article or original layout). arXiv links save the real paper. |
| `marginalia://save?url=<link>` | Same, from Shortcuts (e.g. a Safari share-sheet shortcut) |

## Icon

The app icon is drawn in code: `swift design/make-icon.swift <out-dir>` renders the light, dark and
tinted variants plus the small in-app logo. Copy them into `Marginalia/Resources/Assets.xcassets`.
