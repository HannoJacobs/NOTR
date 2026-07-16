import SwiftUI

struct NoteViewerView: View {
    @Environment(AppState.self) private var appState
    let note: PinnedNote
    var onSizeChanged: (() -> Void)? = nil

    @State private var panelWidth: CGFloat = 420
    @State private var panelHeight: CGFloat = 360
    @State private var dragStartSize: CGSize?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pathBar
            Divider()
            ZStack(alignment: .bottomTrailing) {
                contentArea
                    .frame(width: panelWidth, height: panelHeight)
                resizeHandle
            }
        }
        .frame(width: panelWidth)
        .onAppear {
            panelWidth = CGFloat(note.width)
            panelHeight = CGFloat(note.height)
        }
        .onChange(of: note.id) { _, _ in
            panelWidth = CGFloat(note.width)
            panelHeight = CGFloat(note.height)
        }
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            Text(note.directoryHint)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            // Fixed-width status slot so save state never reflows the pane.
            Group {
                if appState.hasUnsavedChanges {
                    Text("Saving…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else if appState.saveError != nil {
                    Text("Save failed")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 64, alignment: .trailing)
        }
        .frame(width: panelWidth - 24, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var contentArea: some View {
        if appState.isLoadingContent {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = appState.loadError {
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            PlainTextEditor(
                text: Binding(
                    get: { appState.fileContent },
                    set: { appState.updateFileContent($0) }
                ),
                isLineWrappingEnabled: appState.lineWrapEnabled,
                onTextChange: { appState.updateFileContent($0) }
            )
            .padding(4)
        }
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartSize == nil {
                            dragStartSize = CGSize(width: panelWidth, height: panelHeight)
                        }
                        guard let start = dragStartSize else { return }
                        panelWidth = min(900, max(280, start.width + value.translation.width))
                        panelHeight = min(900, max(180, start.height + value.translation.height))
                        onSizeChanged?()
                    }
                    .onEnded { _ in
                        dragStartSize = nil
                        appState.updateSize(
                            for: note.id,
                            width: panelWidth,
                            height: panelHeight
                        )
                        onSizeChanged?()
                    }
            )
            .help("Drag to resize — size is remembered for this note")
    }
}
