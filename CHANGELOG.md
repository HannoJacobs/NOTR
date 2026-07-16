# Changelog

## 0.2

- Fix the bug where clicking an emoji in the macOS Emoji & Symbols (Character Viewer) picker while editing a note would instantly dismiss the NOTR panel, discarding the interaction before the glyph could be inserted.
- Root cause: the panel dismissed itself on a global mouse-down monitor, so any click outside the panel bounds — including clicks landing on the system emoji picker window — was treated as a click-away and closed the panel.
- Replace the global/local mouse-down monitors with an app-deactivation observer (`NSApplication.didResignActiveNotification`); the panel now closes when the user actually switches to another application rather than on raw outside clicks.
- Because the Emoji & Symbols viewer is a non-activating system panel, clicking an emoji keeps NOTR the active app, so the panel stays open and the emoji is inserted into the focused note as expected.
- Keyboard-driven emoji selection (arrow keys plus Return) continues to work exactly as before, and now matches the click-to-insert path so both input methods behave identically.
- Clicking the menu-bar status item still toggles the panel open and closed, since interacting with our own status item does not deactivate the application.
- Clicking into a genuinely different application (Finder, editor, browser, and similar) still dismisses the panel, preserving the normal lightweight menu-bar dismissal behavior.
- Add diagnostic logging for the new dismissal path so future dismiss-related regressions can be traced from the session log under Application Support.
- Bump the shipped build to `0.2` and publish it as the live GitHub release asset via the same ad-hoc DMG packaging and install-verification pipeline used for `0.1`.

## 0.1

- Ship the first NOTR menu-bar quick note viewer as a personal macOS agent app (`LSUIElement`) following the same Swift Package Manager + ad-hoc DMG packaging path used by DICTATR and SOURCR.
- Pin any text-ish file from Finder (markdown, plain text, Python, Swift, JSON, config, and similar) into a persistent quick-view list stored in UserDefaults, with automatic prune when a pinned path disappears from disk.
- Open a pinned file into a monospaced plain-text editor that autosaves on a short debounce after edits, with UTF-8 write-through to the real file on disk and a fixed-width “Saving…” status that never reflows the pane.
- Remember per-note panel width and height so short notes and long docs reopen at the exact size the user last dragged; typing alone never changes the pane size.
- Reorder pins with a grip-handle drag that floats a preview and shows a stable insertion line; order commits only on release so the list stays smooth instead of jittering mid-drag.
- Match system light and dark appearance automatically; expose a Settings toggle for line wrap vs horizontal scroll for long lines.
- Present a borderless rounded panel anchored under the menu-bar note icon with no popover arrow, flush spacing under the status item, and normal menu-bar dismiss-on-click-away behavior.
- Fix first-open `NSOpenPanel` Favorites greying by briefly switching to regular activation when pinning files, and avoid the AppKit/SwiftUI layout recursion crash that previously stack-overflowed when opening a note.
- Add file diagnostics under Application Support (`Logs/latest.log` symlink plus session logs) with version/build/bundlePath launch evidence, plus create-dmg / install-release / release-common scripts for full-send packaging.
- Install verification is gated on the live `/Applications/NOTR.app` launch log showing the expected `0.1` version and build after DMG packaging and GitHub release upload.
