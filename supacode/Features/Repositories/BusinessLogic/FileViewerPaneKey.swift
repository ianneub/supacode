import ComposableArchitecture
import Foundation

nonisolated extension SharedReaderKey where Self == AppStorageKey<Double>.Default {
  /// Persisted left-pane (terminal) fraction of the worktree-detail split, 0...1.
  static var fileViewerSplitRatio: Self {
    Self[.appStorage("fileViewerSplitRatio"), default: 0.6]
  }
}
