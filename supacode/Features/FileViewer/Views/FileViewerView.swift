import ComposableArchitecture
import SwiftUI

/// The side-pane root: changed-file list on top, the selected file's content
/// (Diff or Source) below, with a mode picker and a close button.
struct FileViewerView: View {
  @Bindable var store: StoreOf<FileViewerFeature>

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      fileList
      Divider()
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(.background)
    .task { store.send(.task) }
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

  @ViewBuilder private var fileList: some View {
    switch store.files {
    case .idle, .loading:
      ProgressView().frame(maxWidth: .infinity).frame(height: 120)
    case .loaded(let files):
      if files.isEmpty {
        ContentUnavailableView("No changed files", systemImage: "checkmark.circle")
          .frame(height: 120)
      } else {
        DiffFileListView(
          files: files,
          selectedPath: store.selectedPath,
          onTap: { store.send(.fileTapped($0)) }
        )
        .frame(height: 160)
      }
    case .failed(let message):
      ContentUnavailableView(
        "Couldn't load changes",
        systemImage: "exclamationmark.triangle",
        description: Text(message)
      )
      .frame(height: 120)
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
