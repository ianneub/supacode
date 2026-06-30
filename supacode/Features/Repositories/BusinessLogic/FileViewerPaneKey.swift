import ComposableArchitecture
import Foundation

nonisolated extension SharedReaderKey where Self == AppStorageKey<Double>.Default {
  /// Persisted width (points) of the file-viewer side pane.
  static var fileViewerPaneWidth: Self {
    Self[.appStorage("fileViewerPaneWidth"), default: 400]
  }
}
