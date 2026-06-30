import ComposableArchitecture
import Foundation

nonisolated extension SharedReaderKey where Self == AppStorageKey<Double>.Default {
  /// Persisted width (points) of the file-viewer side pane.
  static var fileViewerPaneWidth: Self {
    Self[.appStorage("fileViewerPaneWidth"), default: 400]
  }

  /// Persisted height (points) of the changed-file list inside the file-viewer pane.
  static var fileViewerFileListHeight: Self {
    Self[.appStorage("fileViewerFileListHeight"), default: 160]
  }
}
