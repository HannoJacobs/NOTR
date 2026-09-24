# NOTR

Menu-bar quick viewer for text notes on macOS. Pin a few files you look at often and open them without firing up a full IDE.

## What it does

- Lives in the menu bar (note icon)
- **+** menu: **New Note** opens a blank untitled draft immediately (caret focused, ready to type), or **Pin Existing…** for text-ish files (`.md`, `.txt`, `.py`, etc.)
- Name the file only after there is content — use the header **Save** icon, or Save appears on Back / **Pin to NOTR**
- While editing, **Pin to NOTR** / **In NOTR** adds or removes the file from your quick-view list (the file always stays on disk)
- Click a pin to open a plain-text editor with autosave
- Drag the corner handle to resize — size is sticky per file, can narrow to roughly two words, and has no fixed upper width or height cap
- On narrow notes, scroll the top header horizontally to reach its controls
- Drag rows to reorder; right-click → remove from NOTR (does not delete the file)
- Missing files are pruned automatically
- Drag the grip to detach the panel into a floating window; it is always kept on a connected display — unplugging the monitor it sat on moves it onto the nearest remaining one
- Follows system light/dark appearance

## Dev run

```bash
./run-dev.sh
```

## Release (full send)

```bash
./create-dmg.sh
./install-release.sh
```

Then upload `NOTR.dmg` to the matching GitHub release tag.
