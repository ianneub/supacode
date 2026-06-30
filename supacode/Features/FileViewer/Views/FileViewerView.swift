import ComposableArchitecture
import SwiftUI

/// The side-pane root: changed-file list on top, the selected file's content
/// (Diff or Source) below, with a mode picker and a close button.
struct FileViewerView: View {
  @Bindable var store: StoreOf<FileViewerFeature>

  /// Persisted file-list height; `liveListHeight` tracks it 1:1 during a drag and
  /// is written back on release (mirrors the pane-width divider).
  @Shared(.fileViewerFileListHeight) private var fileListHeight: Double
  @State private var liveListHeight: Double = 160

  var body: some View {
    GeometryReader { proxy in
      // Keep room for the header + a usable diff area no matter how far the
      // divider is dragged.
      let maxListHeight = max(120, proxy.size.height - 220)
      VStack(spacing: 0) {
        header
        Divider()
        fileList
          .frame(height: min(max(liveListHeight, 100), maxListHeight))
        FileListHeightDivider(
          height: $liveListHeight,
          minHeight: 100,
          maxHeight: maxListHeight,
          onCommit: { $fileListHeight.withLock { $0 = liveListHeight } }
        )
        content
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(.background)
    .task { store.send(.task) }
    .onAppear { liveListHeight = fileListHeight }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Picker("Mode", selection: Binding(get: { store.mode }, set: { store.send(.modeChanged($0)) })) {
        Text("Diff").tag(FileViewerFeature.State.Mode.diff)
        Text("Source").tag(FileViewerFeature.State.Mode.source)
        if let path = store.selectedPath, FileViewerFeature.isMarkdown(path) {
          Text("Preview").tag(FileViewerFeature.State.Mode.preview)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(maxWidth: 220)
      .disabled(store.selectedPath == nil)
      Spacer()
      Button {
        store.send(.closeButtonTapped)
      } label: {
        Image(systemName: "xmark")
          .accessibilityLabel("Close file viewer")
      }
      .buttonStyle(.borderless)
      .help("Close the file viewer")
    }
    .padding(8)
  }

  // Height is controlled by the caller (resizable divider), so each state just
  // fills the space it's given.
  @ViewBuilder private var fileList: some View {
    switch store.files {
    case .idle, .loading:
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    case .loaded(let files):
      if files.isEmpty {
        ContentUnavailableView("No changed files", systemImage: "checkmark.circle")
      } else {
        DiffFileListView(
          files: files,
          selectedPath: store.selectedPath,
          onTap: { store.send(.fileTapped($0)) }
        )
      }
    case .failed(let message):
      ContentUnavailableView(
        "Couldn't load changes",
        systemImage: "exclamationmark.triangle",
        description: Text(message)
      )
    }
  }

  @ViewBuilder private var content: some View {
    switch store.content {
    case .idle:
      ContentUnavailableView("Select a file", systemImage: "doc.text")
    case .loading:
      ProgressView()
    case .loaded(let loaded):
      switch store.mode {
      case .diff:
        if let diff = loaded.fileDiff {
          DiffView(fileDiff: diff)
        } else {
          ContentUnavailableView("Nothing to show", systemImage: "doc")
        }
      case .source:
        SourceView(text: loaded.rawText ?? "")
      case .preview:
        MarkdownPreviewView(text: loaded.rawText ?? "")
      }
    case .failed(let message):
      ContentUnavailableView(
        "Couldn't load file",
        systemImage: "exclamationmark.triangle",
        description: Text(message)
      )
    }
  }
}

/// Horizontal grab strip between the file list and the diff that resizes the
/// list's height. Mirrors `FileViewerPaneDivider`, rotated to the vertical axis.
private struct FileListHeightDivider: View {
  @Binding var height: Double
  let minHeight: Double
  let maxHeight: Double
  let onCommit: () -> Void

  private let grabHeight: CGFloat = 16

  @State private var dragStartHeight: Double?

  var body: some View {
    // Transparent grab strip tall enough to hit easily, with the visible 1pt
    // separator centered in it.
    Color.clear
      .frame(height: grabHeight)
      .frame(maxWidth: .infinity)
      .overlay {
        Rectangle()
          .fill(Color(nsColor: .separatorColor))
          .frame(height: 1)
      }
      .contentShape(.rect)
      .pointerStyle(.frameResize(position: .bottom))
      .gesture(
        // Global space: translation == true cursor movement, so dragging the
        // divider tracks the cursor 1:1 even as the list resizes underneath it.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
          .onChanged { value in
            let start = dragStartHeight ?? height
            if dragStartHeight == nil { dragStartHeight = start }
            height = min(max(minHeight, start + value.translation.height), maxHeight)
          }
          .onEnded { _ in
            dragStartHeight = nil
            onCommit()
          }
      )
  }
}
