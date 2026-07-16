# NOTR

Menu-bar quick viewer for text notes on macOS. Pin a few files you look at often and open them without firing up a full IDE.

## What it does

- Lives in the menu bar (note icon)
- Pin any text-ish files (`.md`, `.txt`, `.py`, etc.) via **+**
- Click a pin to open a plain-text editor with autosave
- Drag the corner handle to resize — size is sticky per file
- Drag rows to reorder; right-click → remove from NOTR (does not delete the file)
- Missing files are pruned automatically
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
