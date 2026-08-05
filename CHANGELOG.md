# Changelog

## 0.8

- Add an explicit header **Save** control (`square.and.arrow.down`) on untitled drafts so you can name and write the note without leaving the editor via Back.
- The Save icon is enabled only after the draft has meaningful content; empty drafts keep it disabled with help text explaining you need to write first.
- Clicking Save runs the same Save dialog as Back / dismiss (suggested filename from the first line, Cancel keeps the draft open) but leaves you in the note afterward so you can keep editing or pin.
- On untitled drafts the Save icon replaces the Reload control (reload remains for file-backed notes); path bar “Unsaved” / “Not saved yet” behavior is unchanged.
- Wire Save through a public `saveUntitledDraft()` path on app state so Pin-to-NOTR and Back continue to share the same finalize/write/watcher pipeline.
- Update README to document the in-note Save affordance alongside Back and Pin to NOTR as ways to name a draft.
- Bump the shipped build to `0.8` and publish it as the live GitHub release asset through the same ad-hoc DMG packaging and install-verification pipeline used for prior releases.
- Keep write-first New Note behavior from `0.7`: no filename prompt until there is content, whether Save is triggered from the new icon or from leaving/pinning.

## 0.7

- Change **New Note** so it no longer blocks on a Save dialog before you can write: choosing New Note opens an untitled in-memory draft immediately.
- Drafts use an empty path (`Untitled` / “Not saved yet”) and stay out of the pin list and off disk until you name them; typing does not autosave to a temporary file.
- The Save dialog appears only after the draft has meaningful content — when you press Back, dismiss the panel, or choose **Pin to NOTR**. Empty drafts discard with no prompt.
- Suggested filename is derived from the first non-empty line of the draft (sanitized, `.md` by default) so naming happens after the note has substance.
- Cancel on the Save dialog keeps the untitled draft open so you can keep editing; successful save writes the UTF-8 file, starts the normal watcher/autosave path, and optionally pins when save was triggered from **Pin to NOTR**.
- Pin is disabled on empty drafts (with help text explaining you need content first); after content exists, Pin runs save-then-pin in one flow.
- Path bar shows “Unsaved” for drafts with content instead of the normal “Saving…” slot; reload is a no-op on untitled drafts.
- Document the write-first / name-later New Note behavior in README and empty-state copy, and record that full send is the default shipping posture in `AGENTS.md`.
- Bump the shipped build to `0.7` and publish it as the live GitHub release asset through the same ad-hoc DMG packaging and install-verification pipeline used for prior releases.

## 0.6

- Add a true **create new note** path so NOTR is no longer limited to pinning files that already exist elsewhere on disk.
- The footer `+` control is now a menu with **New Note…** and **Pin Existing…**; Pin Existing keeps the previous multi-select open-panel flow for text-ish files.
- **New Note…** presents an `NSSavePanel` (same accessory→regular activation dance as the open panel) so you choose folder and filename each time; default name is `Untitled.md`, with markdown and plain-text types allowed.
- Creating a note writes a fresh UTF-8 file at the chosen path, opens it in the plain-text editor immediately, and starts the existing file watcher / autosave pipeline against that real file.
- New notes start **unpinned**: they are not added to the quick-view list until you explicitly opt in, so a throwaway scratch file can stay on disk without cluttering NOTR.
- While any note is open, the header shows a labeled **Pin to NOTR** / **In NOTR** control for list membership. This is separate from the existing pin-glyph control, which still means “keep the panel open while working in other apps.”
- Toggling list membership on appends the open note (including its current size) into `pinnedNotes` and persists it; toggling off removes it from the list but keeps the editor open and never deletes the file.
- Viewer state is driven by `openNote`, which may or may not be in `pinnedNotes`, so unpinned drafts and pinned notes share one editor path. Going Back leaves an unpinned file on disk only; missing files still prune from the list and clear a deleted open note.
- Empty-state and README copy now mention creating a new note as well as pinning existing files.
- Bump the shipped build to `0.6` and publish it as the live GitHub release asset through the same ad-hoc DMG packaging and install-verification pipeline used for prior releases.

## 0.5

- Fix multi-monitor panel placement so clicking the menu-bar icon on one display no longer opens NOTR on a different display (especially common with vertically stacked screens).
- Root cause: `pinToAnchor` clamped the panel origin against `panel.screen ?? NSScreen.main`. After a prior show — or while the panel still sat at its initial `(0,0)` frame — that screen was often the primary/previous display, so edge clamping shoved the window onto the wrong monitor.
- Resolve the anchor screen from the click itself: prefer the `NSScreen` that contains the mouse location, then the screen that intersects the status-item button frame, and never reuse a stale `panel.screen` for clamping.
- When the status-item button window still reports the primary display's frame after a click on a secondary menu bar (a known multi-monitor AppKit quirk), rebuild the anchor from the click screen's menu-bar bottom and the mouse X so the panel stays under the icon the user actually clicked.
- Horizontal drift ("way left" / "way right" on the correct screen) came from the same wrong-screen clamp: forcing X into another display's `visibleFrame` pushed the panel to that display's edge instead of centering under the icon.
- Keep edge clamping, but only against the resolved click/status-item screen's `visibleFrame`, and keep the panel tucked under that screen's menu bar when height allows.
- Add diagnostic logging for the chosen anchor point, screen frame, and the wrong-screen fallback path so multi-monitor placement regressions are visible in the Application Support session log.
- Bump the shipped build to `0.5` and publish it as the live GitHub release asset through the same ad-hoc DMG packaging and install-verification pipeline used for prior releases.

## 0.4

- Add a pin / keep-on-top toggle so NOTR can stay hovering while you work in another app — useful when reading a note and typing or browsing "behind" it without the panel auto-closing.
- The pin control lives in the note header (next to reload) and in the pin-list footer, so it is available both while viewing a note and from the list overview; it is an overall app setting, not per-note.
- When pinned, the panel skips both auto-dismiss paths (app-deactivation and menu-bar-strip clicks), drops to a floating window level so it stays above document windows, and remains visible after you click into Finder, an editor, a browser, or another app.
- When unpinned, normal menu-bar dismissal returns immediately (hybrid resign-active + menu-bar-strip monitor from `0.3`); if you unpin after already switching away, the panel hides right away instead of lingering.
- Explicit close still works while pinned: clicking the menu-bar status item toggles the panel closed. Pin state is persisted in UserDefaults and survives hide/show and relaunches until you unpin.
- Active pin state is visually obvious — filled `pin.fill` glyph plus an accent-tinted button background — matching the existing press/feedback rule for every clickable control.
- Keep the emoji/Character Viewer behavior from `0.2`/`0.3` intact: pinning only disables auto-dismiss; it does not reintroduce a blanket outside-click monitor that would swallow emoji clicks.
- Add diagnostic logging for pin on/off and for "staying open (pinned)" on resign-active so sticky-mode regressions are easy to trace from the Application Support session log.
- Bump the shipped build to `0.4` and publish it as the live GitHub release asset through the same ad-hoc DMG packaging and install-verification pipeline used for prior releases.

## 0.3

- Fix the bug where clicking a different menu-bar icon while the NOTR panel was open left NOTR lingering on top, so the other item's menu opened underneath it instead of NOTR closing first.
- Root cause: after `0.2` moved dismissal onto `NSApplication.didResignActiveNotification` (to keep the emoji picker working), clicking another menu-bar item never deactivates NOTR — the other item just opens a transient tracking menu — so no dismiss ever fired for that interaction.
- Add a global mouse-down monitor that closes NOTR when a click lands in the menu-bar strip, so clicking any other menu-bar icon now dismisses NOTR immediately and the other menu opens cleanly on top, matching SOURCR's open/close feel.
- Deliberately scope the monitor to menu-bar-strip clicks only, so the macOS Emoji & Symbols (Character Viewer) picker — a non-activating panel that floats below the menu bar — is never treated as a dismiss trigger; the `0.2` emoji-insert fix stays intact.
- Keep the `NSApplication.didResignActiveNotification` observer for genuine app switches (Finder, editor, browser), so switching to another application still dismisses the panel exactly as before.
- Ignore clicks on NOTR's own status item inside the monitor so the icon still toggles the panel open and closed instead of double-dismissing, and ignore in-panel clicks so editing and reordering are unaffected.
- Compute the menu-bar strip from the clicked screen's `frame`/`visibleFrame` inset (falling back to `NSStatusBar.system.thickness`) so the detection works across multiple displays and notch/no-notch layouts.
- Add diagnostic logging (`menu-bar click outside NOTR; dismissing panel`) for the new dismissal path so future dismiss regressions remain traceable from the session log under Application Support.
- Bump the shipped build to `0.3` and publish it as the live GitHub release asset through the same ad-hoc DMG packaging and install-verification pipeline used for `0.1` and `0.2`.

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
