import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

@Observable
final class AppState {
    private static let pinsKey = "notr.pinnedNotes"
    private static let lastSelectedKey = "notr.lastSelectedNoteID"
    private static let lineWrapKey = "notr.lineWrapEnabled"
    private static let panelPinnedKey = "notr.panelPinned"

    var pinnedNotes: [PinnedNote] = [] {
        didSet { persistPins() }
    }

    /// Note currently open in the viewer. May or may not be in `pinnedNotes`.
    var openNote: PinnedNote?

    /// Persisted ID of the last *pinned* note opened (for restore on launch).
    var selectedNoteID: UUID? {
        didSet {
            if let selectedNoteID {
                UserDefaults.standard.set(selectedNoteID.uuidString, forKey: Self.lastSelectedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastSelectedKey)
            }
        }
    }

    var lineWrapEnabled: Bool {
        didSet {
            UserDefaults.standard.set(lineWrapEnabled, forKey: Self.lineWrapKey)
        }
    }

    /// When true, the panel stays open while working in other apps (no auto-dismiss).
    var isPanelPinned: Bool {
        didSet {
            UserDefaults.standard.set(isPanelPinned, forKey: Self.panelPinnedKey)
            Log.info("panel pin \(isPanelPinned ? "on" : "off")", "appState")
            onPanelPinnedChanged?(isPanelPinned)
        }
    }

    /// Hook for StatusPanelController to react when pin toggles (e.g. unpin while inactive → hide).
    var onPanelPinnedChanged: ((Bool) -> Void)?

    var fileContent: String = ""
    var loadError: String?
    var isLoadingContent = false
    var saveError: String?
    var hasUnsavedChanges = false

    private var fileWatcher: DispatchSourceFileSystemObject?
    private var watchedDescriptor: Int32 = -1
    private var saveWorkItem: DispatchWorkItem?
    private var ignoreWatcherUntil: Date?
    private var isApplyingExternalReload = false

    init() {
        if UserDefaults.standard.object(forKey: Self.lineWrapKey) == nil {
            lineWrapEnabled = true
        } else {
            lineWrapEnabled = UserDefaults.standard.bool(forKey: Self.lineWrapKey)
        }
        isPanelPinned = UserDefaults.standard.bool(forKey: Self.panelPinnedKey)

        loadPins()
        pruneMissingNotes()
        if let saved = UserDefaults.standard.string(forKey: Self.lastSelectedKey),
           let id = UUID(uuidString: saved),
           let note = pinnedNotes.first(where: { $0.id == id }) {
            selectedNoteID = id
            openNote = note
            loadSelectedContent(restartWatcher: true)
        }
    }

    func togglePanelPinned() {
        isPanelPinned.toggle()
    }

    /// Compatibility alias for the note currently in the viewer.
    var selectedNote: PinnedNote? { openNote }

    var isUntitledDraft: Bool {
        openNote?.isUntitledDraft == true
    }

    var hasMeaningfulContent: Bool {
        !fileContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isOpenNotePinned: Bool {
        guard let openNote, !openNote.isUntitledDraft else { return false }
        return pinnedNotes.contains { $0.path == openNote.path }
    }

    func toggleOpenNotePinned() {
        guard let note = openNote else { return }
        if note.isUntitledDraft {
            guard hasMeaningfulContent else {
                Log.info("pin ignored: untitled draft has no content yet", "appState")
                return
            }
            promptSaveLocation(pinAfterSave: true, leaveAfterSave: false)
            return
        }
        if let index = pinnedNotes.firstIndex(where: { $0.path == note.path }) {
            let removed = pinnedNotes[index]
            pinnedNotes.remove(at: index)
            if selectedNoteID == removed.id || selectedNoteID == note.id {
                selectedNoteID = nil
            }
            Log.info("note list pin off path=\(note.path)", "appState")
        } else {
            var next = pinnedNotes
            next.append(note)
            pinnedNotes = next
            selectedNoteID = note.id
            Log.info("note list pin on path=\(note.path)", "appState")
        }
    }

    func pruneMissingNotes() {
        let existing = pinnedNotes.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing.count != pinnedNotes.count {
            pinnedNotes = existing
        }
        if let openNote, !openNote.isUntitledDraft,
           !FileManager.default.fileExists(atPath: openNote.path) {
            Log.info("open note missing on disk; clearing path=\(openNote.path)", "appState")
            clearSelection()
            return
        }
        if let selectedNoteID, !pinnedNotes.contains(where: { $0.id == selectedNoteID }) {
            self.selectedNoteID = nil
        }
    }

    func addNotes(from urls: [URL]) {
        var next = pinnedNotes
        for url in urls {
            let path = url.path
            guard FileManager.default.fileExists(atPath: path) else { continue }
            guard !next.contains(where: { $0.path == path }) else { continue }
            next.append(PinnedNote(path: path))
        }
        pinnedNotes = next
    }

    func removeNote(_ note: PinnedNote) {
        pinnedNotes.removeAll { $0.id == note.id || $0.path == note.path }
        if selectedNoteID == note.id {
            selectedNoteID = nil
        }
        // Keep the editor open if this was the open note; only Back leaves.
    }

    func movePinnedNote(from fromIndex: Int, to toIndex: Int) {
        guard fromIndex != toIndex,
              pinnedNotes.indices.contains(fromIndex),
              pinnedNotes.indices.contains(toIndex)
        else { return }
        var notes = pinnedNotes
        let item = notes.remove(at: fromIndex)
        notes.insert(item, at: toIndex)
        pinnedNotes = notes
    }

    func selectNote(_ note: PinnedNote) {
        Log.info("selectNote name=\(note.displayName) path=\(note.path)", "appState")
        if isUntitledDraft && hasMeaningfulContent {
            promptSaveLocation(pinAfterSave: false, leaveAfterSave: false) { [weak self] saved in
                guard let self, saved else { return }
                self.openPinnedNote(note)
            }
            return
        }
        flushPendingSave()
        openPinnedNote(note)
    }

    func clearSelection() {
        if isUntitledDraft && hasMeaningfulContent {
            // Ask for a filename only once there is content; Cancel keeps the draft open.
            promptSaveLocation(pinAfterSave: false, leaveAfterSave: true)
            return
        }
        discardOpenNote()
    }

    func updateSize(for noteID: UUID, width: CGFloat, height: CGFloat) {
        let clampedWidth = max(280, min(900, Double(width)))
        let clampedHeight = max(180, min(900, Double(height)))

        if var open = openNote, open.id == noteID {
            if abs(open.width - clampedWidth) >= 1 || abs(open.height - clampedHeight) >= 1 {
                open.width = clampedWidth
                open.height = clampedHeight
                openNote = open
            }
        }

        guard let index = pinnedNotes.firstIndex(where: { $0.id == noteID }) else { return }
        if abs(pinnedNotes[index].width - clampedWidth) < 1,
           abs(pinnedNotes[index].height - clampedHeight) < 1 {
            return
        }
        pinnedNotes[index].width = clampedWidth
        pinnedNotes[index].height = clampedHeight
    }

    func reloadSelectedContent() {
        guard !isUntitledDraft else { return }
        flushPendingSave()
        loadSelectedContent(restartWatcher: true)
    }

    func flushPendingSaveIfNeeded() {
        if isUntitledDraft && hasMeaningfulContent {
            promptSaveLocation(pinAfterSave: false, leaveAfterSave: true)
            return
        }
        if isUntitledDraft {
            discardOpenNote()
            return
        }
        flushPendingSave()
    }

    func updateFileContent(_ newValue: String) {
        if isApplyingExternalReload { return }
        guard newValue != fileContent else { return }
        fileContent = newValue
        hasUnsavedChanges = true
        saveError = nil
        if isUntitledDraft {
            // Stay in memory until the user names the file (after there is content).
            return
        }
        scheduleSave()
    }

    /// Opens a blank untitled draft immediately — no Save dialog until there is content.
    func createNewNote() {
        if isUntitledDraft && !hasMeaningfulContent {
            // Already on an empty draft; keep it.
            return
        }
        if isUntitledDraft && hasMeaningfulContent {
            promptSaveLocation(pinAfterSave: false, leaveAfterSave: false) { [weak self] saved in
                guard let self, saved else { return }
                self.beginUntitledDraft()
            }
            return
        }
        flushPendingSave()
        beginUntitledDraft()
    }

    func pickFiles() {
        // MenuBarExtra + LSUIElement accessory apps often break the first NSOpenPanel
        // (sidebar Favorites grayed out). Become a regular app, activate, then present.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }

                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = true
                panel.canCreateDirectories = false
                panel.title = "Pin notes to NOTR"
                panel.message = "Choose text files to keep in your quick view."
                panel.prompt = "Pin"
                panel.center()

                panel.begin { [weak self] response in
                    NSApp.setActivationPolicy(.accessory)
                    guard let self, response == .OK else { return }
                    self.addNotes(from: panel.urls)
                }
            }
        }
    }

    private func beginUntitledDraft() {
        stopWatching()
        saveWorkItem?.cancel()
        saveWorkItem = nil
        openNote = PinnedNote(path: "")
        selectedNoteID = nil
        fileContent = ""
        loadError = nil
        saveError = nil
        hasUnsavedChanges = false
        isLoadingContent = false
        Log.info("opened untitled draft", "appState")
    }

    private func openPinnedNote(_ note: PinnedNote) {
        openNote = note
        selectedNoteID = note.id
        loadSelectedContent(restartWatcher: true)
    }

    private func discardOpenNote() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        stopWatching()
        openNote = nil
        selectedNoteID = nil
        fileContent = ""
        loadError = nil
        saveError = nil
        hasUnsavedChanges = false
        isLoadingContent = false
    }

    /// Suggested name from the first non-empty line of the draft body.
    private func suggestedFileName(from content: String) -> String {
        let firstLine = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "Untitled"
        var base = String(firstLine.prefix(48))
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        base = base.components(separatedBy: invalid).joined(separator: "-")
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
        if base.isEmpty { base = "Untitled" }
        if base.lowercased().hasSuffix(".md") || base.lowercased().hasSuffix(".txt") {
            return base
        }
        return "\(base).md"
    }

    private func promptSaveLocation(
        pinAfterSave: Bool,
        leaveAfterSave: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard isUntitledDraft else {
            completion?(false)
            return
        }
        guard hasMeaningfulContent else {
            completion?(false)
            return
        }

        let suggested = suggestedFileName(from: fileContent)
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }

                let panel = NSSavePanel()
                panel.canCreateDirectories = true
                panel.title = "Save Note"
                panel.message = "Choose a name and location for this note."
                panel.prompt = "Save"
                panel.nameFieldStringValue = suggested
                panel.allowedContentTypes = [
                    UTType(filenameExtension: "md") ?? .plainText,
                    .plainText,
                ]
                panel.center()

                panel.begin { [weak self] response in
                    NSApp.setActivationPolicy(.accessory)
                    guard let self else { return }
                    guard response == .OK, let url = panel.url else {
                        completion?(false)
                        return
                    }
                    let ok = self.finalizeDraft(to: url, pin: pinAfterSave)
                    if ok, leaveAfterSave {
                        self.discardOpenNote()
                    }
                    completion?(ok)
                }
            }
        }
    }

    @discardableResult
    private func finalizeDraft(to url: URL, pin: Bool) -> Bool {
        guard var note = openNote, note.isUntitledDraft else { return false }
        do {
            try fileContent.write(to: url, atomically: true, encoding: .utf8)
            note.path = url.path
            openNote = note
            hasUnsavedChanges = false
            saveError = nil
            startWatching(path: note.path)
            Log.info("saved new note path=\(note.path) bytes=\(fileContent.utf8.count)", "appState")
            if pin {
                if !pinnedNotes.contains(where: { $0.path == note.path }) {
                    var next = pinnedNotes
                    next.append(note)
                    pinnedNotes = next
                }
                selectedNoteID = note.id
                Log.info("note list pin on path=\(note.path)", "appState")
            }
            return true
        } catch {
            saveError = error.localizedDescription
            Log.error("save new note failed path=\(url.path) error=\(error.localizedDescription)", "appState")
            return false
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveSelectedContent()
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func flushPendingSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        if hasUnsavedChanges {
            saveSelectedContent()
        }
    }

    private func saveSelectedContent() {
        guard let note = openNote, !note.isUntitledDraft else { return }
        guard hasUnsavedChanges else { return }

        do {
            ignoreWatcherUntil = Date().addingTimeInterval(1.0)
            try fileContent.write(to: note.url, atomically: true, encoding: .utf8)
            hasUnsavedChanges = false
            saveError = nil
            Log.info("saved bytes=\(fileContent.utf8.count) path=\(note.path)", "appState")
        } catch {
            saveError = error.localizedDescription
            Log.error("save failed path=\(note.path) error=\(error.localizedDescription)", "appState")
        }
    }

    private func loadSelectedContent(restartWatcher: Bool) {
        if restartWatcher {
            stopWatching()
        }

        guard let note = openNote else {
            fileContent = ""
            loadError = nil
            return
        }

        if note.isUntitledDraft {
            return
        }

        guard FileManager.default.fileExists(atPath: note.path) else {
            Log.info("load skipped: file missing, pruning path=\(note.path)", "appState")
            pruneMissingNotes()
            return
        }

        isLoadingContent = true
        loadError = nil

        do {
            let data = try Data(contentsOf: note.url)
            if let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) {
                isApplyingExternalReload = true
                fileContent = text
                isApplyingExternalReload = false
                hasUnsavedChanges = false
                Log.info("loaded bytes=\(data.count) restartWatcher=\(restartWatcher) path=\(note.path)", "appState")
            } else {
                fileContent = ""
                loadError = "Could not decode this file as text."
                Log.error("decode failed path=\(note.path)", "appState")
            }
            if restartWatcher || fileWatcher == nil {
                startWatching(path: note.path)
            }
        } catch {
            fileContent = ""
            loadError = error.localizedDescription
            Log.error("load failed path=\(note.path) error=\(error.localizedDescription)", "appState")
        }

        isLoadingContent = false
    }

    private func startWatching(path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            if events.contains(.delete) || events.contains(.rename) {
                self.pruneMissingNotes()
                return
            }
            if let until = self.ignoreWatcherUntil, Date() < until {
                return
            }
            if self.hasUnsavedChanges {
                return
            }
            self.loadSelectedContent(restartWatcher: false)
        }
        source.setCancelHandler {
            close(fd)
        }
        fileWatcher = source
        source.resume()
    }

    private func stopWatching() {
        fileWatcher?.cancel()
        fileWatcher = nil
        watchedDescriptor = -1
    }

    private func loadPins() {
        guard let data = UserDefaults.standard.data(forKey: Self.pinsKey) else { return }
        do {
            pinnedNotes = try JSONDecoder().decode([PinnedNote].self, from: data)
        } catch {
            pinnedNotes = []
        }
    }

    private func persistPins() {
        do {
            let data = try JSONEncoder().encode(pinnedNotes)
            UserDefaults.standard.set(data, forKey: Self.pinsKey)
        } catch {
            // Best-effort persistence for the prototype.
        }
    }
}
