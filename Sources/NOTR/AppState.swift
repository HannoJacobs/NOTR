import AppKit
import Foundation
import Observation
import SwiftUI

@Observable
final class AppState {
    private static let pinsKey = "notr.pinnedNotes"
    private static let lastSelectedKey = "notr.lastSelectedNoteID"
    private static let lineWrapKey = "notr.lineWrapEnabled"

    var pinnedNotes: [PinnedNote] = [] {
        didSet { persistPins() }
    }

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

        loadPins()
        pruneMissingNotes()
        if let saved = UserDefaults.standard.string(forKey: Self.lastSelectedKey),
           let id = UUID(uuidString: saved),
           pinnedNotes.contains(where: { $0.id == id }) {
            selectedNoteID = id
            loadSelectedContent(restartWatcher: true)
        }
    }

    var selectedNote: PinnedNote? {
        guard let selectedNoteID else { return nil }
        return pinnedNotes.first(where: { $0.id == selectedNoteID })
    }

    func pruneMissingNotes() {
        let existing = pinnedNotes.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing.count != pinnedNotes.count {
            pinnedNotes = existing
        }
        if let selectedNoteID, !pinnedNotes.contains(where: { $0.id == selectedNoteID }) {
            clearSelection()
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
        if selectedNoteID == note.id {
            clearSelection()
        }
        pinnedNotes.removeAll { $0.id == note.id }
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
        flushPendingSave()
        selectedNoteID = note.id
        loadSelectedContent(restartWatcher: true)
    }

    func clearSelection() {
        flushPendingSave()
        stopWatching()
        selectedNoteID = nil
        fileContent = ""
        loadError = nil
        saveError = nil
        hasUnsavedChanges = false
        isLoadingContent = false
    }

    func updateSize(for noteID: UUID, width: CGFloat, height: CGFloat) {
        guard let index = pinnedNotes.firstIndex(where: { $0.id == noteID }) else { return }
        let clampedWidth = max(280, min(900, Double(width)))
        let clampedHeight = max(180, min(900, Double(height)))
        if abs(pinnedNotes[index].width - clampedWidth) < 1,
           abs(pinnedNotes[index].height - clampedHeight) < 1 {
            return
        }
        pinnedNotes[index].width = clampedWidth
        pinnedNotes[index].height = clampedHeight
    }

    func reloadSelectedContent() {
        flushPendingSave()
        loadSelectedContent(restartWatcher: true)
    }

    func flushPendingSaveIfNeeded() {
        flushPendingSave()
    }

    func updateFileContent(_ newValue: String) {
        if isApplyingExternalReload { return }
        guard newValue != fileContent else { return }
        fileContent = newValue
        hasUnsavedChanges = true
        saveError = nil
        scheduleSave()
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
        guard let note = selectedNote else { return }
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

        guard let note = selectedNote else {
            fileContent = ""
            loadError = nil
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
