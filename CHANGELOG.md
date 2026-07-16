# Changelog

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
