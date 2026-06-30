import Foundation

/// Generic async-load state for the file viewer's file list and file content.
nonisolated enum FileViewerLoadState<Value: Equatable & Sendable>: Equatable, Sendable {
  case idle
  case loading
  case loaded(Value)
  case failed(String)

  var value: Value? {
    if case .loaded(let value) = self { value } else { nil }
  }
}
