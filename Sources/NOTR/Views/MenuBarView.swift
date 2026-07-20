import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    var onClose: (() -> Void)?
    var onContentSizeMayHaveChanged: (() -> Void)?

    @State private var showingSettings = false
    @State private var draggingNoteID: UUID?
    @State private var dragOriginIndex: Int?
    @State private var dragTargetIndex: Int?
    @State private var dragTranslation: CGFloat = 0

    private let rowHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            if showingSettings {
                settingsPanel
            } else if let note = appState.selectedNote {
                noteHeader
                Divider()
                NoteViewerView(
                    note: note,
                    onSizeChanged: { onContentSizeMayHaveChanged?() }
                )
                .environment(appState)
            } else {
                pinList
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.pruneMissingNotes()
            onContentSizeMayHaveChanged?()
        }
        .onChange(of: appState.selectedNoteID) { _, _ in
            DispatchQueue.main.async { onContentSizeMayHaveChanged?() }
        }
        .onChange(of: showingSettings) { _, _ in
            DispatchQueue.main.async { onContentSizeMayHaveChanged?() }
        }
        .onChange(of: appState.pinnedNotes.count) { _, _ in
            DispatchQueue.main.async { onContentSizeMayHaveChanged?() }
        }
    }

    private var noteHeader: some View {
        HStack(spacing: 8) {
            Button {
                appState.clearSelection()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NotrIconButtonStyle())
            .help("Back to pin list")

            Text(appState.selectedNote?.displayName ?? "")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            pinToggleButton

            Button {
                appState.reloadSelectedContent()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NotrIconButtonStyle())
            .help("Reload file")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var pinToggleButton: some View {
        Button {
            appState.togglePanelPinned()
        } label: {
            Image(systemName: appState.isPanelPinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(NotrIconButtonStyle(isActive: appState.isPanelPinned))
        .help(appState.isPanelPinned ? "Unpin panel (auto-closes when you click away)" : "Pin panel (stay open while working elsewhere)")
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    showingSettings = false
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(NotrTextButtonStyle())

                Spacer()

                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Color.clear.frame(width: 44, height: 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            Toggle("Line wrap", isOn: Binding(
                get: { appState.lineWrapEnabled },
                set: { appState.lineWrapEnabled = $0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(14)

            Text("When off, long lines scroll horizontally.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)

            Spacer(minLength: 0)
        }
        .frame(width: 320, height: 160)
    }

    private var pinList: some View {
        VStack(spacing: 0) {
            if appState.pinnedNotes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(appState.pinnedNotes.enumerated()), id: \.element.id) { index, note in
                            pinRow(note, index: index)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .coordinateSpace(name: "pinList")
                    .overlay(alignment: .topLeading) {
                        if let lineY = insertionLineY {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                                .padding(.horizontal, 16)
                                .offset(y: lineY)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .scrollDisabled(draggingNoteID != nil)
                .frame(width: 320, height: listHeight)
            }

            Divider()
            footer
        }
    }

    private var listHeight: CGFloat {
        let rows = CGFloat(appState.pinnedNotes.count)
        return min(360, max(120, rows * rowHeight + 8))
    }

    /// Y position for the drop marker; nil when not dragging to a new slot.
    private var insertionLineY: CGFloat? {
        guard draggingNoteID != nil,
              let origin = dragOriginIndex,
              let target = dragTargetIndex,
              origin != target
        else { return nil }

        let slot = target < origin ? target : target + 1
        // Account for top padding inside the list stack.
        return 4 + CGFloat(slot) * rowHeight - 1
    }

    private func pinRow(_ note: PinnedNote, index: Int) -> some View {
        let isDragging = draggingNoteID == note.id

        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isDragging ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 36)
                .contentShape(Rectangle())
                .highPriorityGesture(reorderGesture(for: note, at: index))
                .help("Drag up or down to reorder")

            Button {
                guard draggingNoteID == nil else { return }
                appState.selectNote(note)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(note.directoryHint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(NotrRowButtonStyle())
            .disabled(isDragging)
        }
        .padding(.horizontal, 4)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDragging ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        // Keep other rows still; only the dragged row floats under the cursor.
        .opacity(isDragging ? 0.35 : 1)
        .overlay(alignment: .top) {
            if isDragging {
                floatingDragPreview(for: note)
                    .offset(y: dragTranslation)
            }
        }
        .zIndex(isDragging ? 10 : 0)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([note.url])
            }
            Button("Remove from NOTR", role: .destructive) {
                appState.removeNote(note)
            }
        }
    }

    private func floatingDragPreview(for note: PinnedNote) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(note.directoryHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
        )
        .allowsHitTesting(false)
    }

    private func reorderGesture(for note: PinnedNote, at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("pinList"))
            .onChanged { value in
                if draggingNoteID == nil {
                    draggingNoteID = note.id
                    dragOriginIndex = index
                    dragTargetIndex = index
                }
                guard draggingNoteID == note.id, let origin = dragOriginIndex else { return }

                // Follow the pointer 1:1 with no animation.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragTranslation = value.translation.height
                }

                let proposed = clampedTargetIndex(
                    origin: origin,
                    translation: value.translation.height,
                    count: appState.pinnedNotes.count
                )
                if proposed != dragTargetIndex {
                    withTransaction(transaction) {
                        dragTargetIndex = proposed
                    }
                }
            }
            .onEnded { _ in
                let origin = dragOriginIndex
                let target = dragTargetIndex

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    draggingNoteID = nil
                    dragOriginIndex = nil
                    dragTargetIndex = nil
                    dragTranslation = 0
                }

                if let origin, let target, origin != target {
                    appState.movePinnedNote(from: origin, to: target)
                }
            }
    }

    /// Stable target index with hysteresis so the marker doesn't flicker at midpoints.
    private func clampedTargetIndex(origin: Int, translation: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let current = dragTargetIndex ?? origin
        let raw = translation / rowHeight
        var proposed = origin + Int(raw.rounded())
        proposed = max(0, min(count - 1, proposed))

        // Require crossing ~60% of a row before accepting a new slot.
        let distanceFromCurrentSlot = abs(raw - CGFloat(current - origin))
        if proposed != current, distanceFromCurrentSlot < 0.6 {
            return current
        }
        return proposed
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "note.text")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("No pinned notes yet")
                .font(.system(size: 13, weight: .medium))
            Text("Click + to pin a text, markdown, or code file for quick viewing.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(width: 320, height: 160)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            pinToggleButton

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NotrIconButtonStyle())
            .help("Settings")

            Button {
                appState.pickFiles()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NotrIconButtonStyle())
            .help("Pin a file")

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(NotrTextButtonStyle())
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
