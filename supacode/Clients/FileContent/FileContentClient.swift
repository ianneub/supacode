import ComposableArchitecture
import Foundation

/// Reads a file's UTF-8 text from disk. Injectable so the FileViewer's
/// source/preview loading is testable without touching the filesystem.
struct FileContentClient: Sendable {
  var read: @Sendable (_ fileURL: URL) async throws -> String
}

extension FileContentClient: DependencyKey {
  static let liveValue = FileContentClient(
    read: { url in try String(contentsOf: url, encoding: .utf8) }
  )

  /// Tests must override `read`; the default throws to surface unstubbed use.
  static let testValue = FileContentClient(
    read: { _ in throw FileContentError.notStubbed }
  )
}

enum FileContentError: Error, Equatable {
  case notStubbed
}

extension DependencyValues {
  var fileContent: FileContentClient {
    get { self[FileContentClient.self] }
    set { self[FileContentClient.self] = newValue }
  }
}
