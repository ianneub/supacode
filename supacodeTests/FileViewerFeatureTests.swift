import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

@MainActor
struct FileViewerFeatureTests {
  private let worktreeURL = URL(fileURLWithPath: "/tmp/wt")

  private func summary(_ path: String) -> DiffFileSummary {
    DiffFileSummary(status: .modified, oldPath: nil, newPath: path, added: 1, removed: 0, isBinary: false)
  }

  @Test func taskLoadsChangedFilesAndAutoSelectsFirstInDiffMode() async {
    let files = [summary("a.swift"), summary("b.swift")]
    let diff = FileDiff(path: "a.swift", isBinary: false, hunks: [])
    let store = TestStore(initialState: FileViewerFeature.State(worktreeURL: worktreeURL)) {
      FileViewerFeature()
    } withDependencies: {
      $0.gitClient.changedFiles = { _, _ in files }
      $0.gitClient.fileDiff = { _, _, _ in diff }
    }

    await store.send(.task) {
      $0.files = .loading
    }
    await store.receive(\.filesLoaded) {
      $0.files = .loaded(files)
      $0.selectedPath = "a.swift"
      $0.mode = .diff
      $0.content = .loading
    }
    await store.receive(\.contentLoaded) {
      $0.content = .loaded(FileViewerFeature.State.Loaded(rawText: nil, fileDiff: diff))
    }
  }

  @Test func taskWithNoChangedFilesLeavesSelectionEmpty() async {
    let store = TestStore(initialState: FileViewerFeature.State(worktreeURL: worktreeURL)) {
      FileViewerFeature()
    } withDependencies: {
      $0.gitClient.changedFiles = { _, _ in [] }
    }
    await store.send(.task) { $0.files = .loading }
    await store.receive(\.filesLoaded) {
      $0.files = .loaded([])
    }
  }

  @Test func filesFailedStoresMessage() async {
    let store = TestStore(initialState: FileViewerFeature.State(worktreeURL: worktreeURL)) {
      FileViewerFeature()
    } withDependencies: {
      $0.gitClient.changedFiles = { _, _ in
        throw GitClientError.commandFailed(command: "changed-files", message: "")
      }
    }
    await store.send(.task) { $0.files = .loading }
    await store.receive(\.filesFailed) {
      $0.files = .failed("Git command failed: changed-files")
    }
  }

  @Test func fileTappedLoadsDiff() async {
    let diff = FileDiff(path: "c.swift", isBinary: false, hunks: [])
    let store = TestStore(
      initialState: FileViewerFeature.State(worktreeURL: worktreeURL, files: .loaded([summary("c.swift")]))
    ) {
      FileViewerFeature()
    } withDependencies: {
      $0.gitClient.fileDiff = { _, path, _ in
        #expect(path == "c.swift")
        return diff
      }
    }
    await store.send(.fileTapped("c.swift")) {
      $0.selectedPath = "c.swift"
      $0.mode = .diff
      $0.content = .loading
    }
    await store.receive(\.contentLoaded) {
      $0.content = .loaded(FileViewerFeature.State.Loaded(rawText: nil, fileDiff: diff))
    }
  }

  @Test func modeChangedToSourceReadsFileText() async {
    let store = TestStore(
      initialState: FileViewerFeature.State(
        worktreeURL: worktreeURL,
        selectedPath: "a.swift",
        mode: .diff,
        content: .loaded(.init(rawText: nil, fileDiff: FileDiff(path: "a.swift", isBinary: false, hunks: [])))
      )
    ) {
      FileViewerFeature()
    } withDependencies: {
      $0.fileContent.read = { url in
        #expect(url.path == "/tmp/wt/a.swift")
        return "let x = 1\n"
      }
    }
    await store.send(.modeChanged(.source)) {
      $0.mode = .source
      $0.content = .loading
    }
    await store.receive(\.contentLoaded) {
      $0.content = .loaded(FileViewerFeature.State.Loaded(rawText: "let x = 1\n", fileDiff: nil))
    }
  }

  @Test func closeButtonEmitsDelegate() async {
    let store = TestStore(initialState: FileViewerFeature.State(worktreeURL: worktreeURL)) {
      FileViewerFeature()
    }
    await store.send(.closeButtonTapped)
    await store.receive(\.delegate.close)
  }
}
