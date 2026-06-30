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

  @Test func modeChangedToPreviewReadsFileTextLikeSource() async {
    let store = TestStore(
      initialState: FileViewerFeature.State(
        worktreeURL: worktreeURL,
        selectedPath: "README.md",
        mode: .diff,
        content: .loaded(.init(rawText: nil, fileDiff: FileDiff(path: "README.md", isBinary: false, hunks: [])))
      )
    ) {
      FileViewerFeature()
    } withDependencies: {
      $0.fileContent.read = { url in
        #expect(url.path == "/tmp/wt/README.md")
        return "# Title\n"
      }
    }
    await store.send(.modeChanged(.preview)) {
      $0.mode = .preview
      $0.content = .loading
    }
    await store.receive(\.contentLoaded) {
      $0.content = .loaded(FileViewerFeature.State.Loaded(rawText: "# Title\n", fileDiff: nil))
    }
  }

  @Test func fileTappedPreservesModeButFallsBackFromPreviewOnNonMarkdown() async {
    // In preview mode, tapping a non-markdown file falls back to source (preview invalid there).
    let store = TestStore(
      initialState: FileViewerFeature.State(
        worktreeURL: worktreeURL,
        files: .loaded([summary("a.swift")]),
        selectedPath: "README.md",
        mode: .preview
      )
    ) {
      FileViewerFeature()
    } withDependencies: {
      $0.fileContent.read = { _ in "let x = 1\n" }
    }
    await store.send(.fileTapped("a.swift")) {
      $0.selectedPath = "a.swift"
      $0.mode = .source  // preview not valid for .swift → fall back to source
      $0.content = .loading
    }
    await store.receive(\.contentLoaded) {
      $0.content = .loaded(FileViewerFeature.State.Loaded(rawText: "let x = 1\n", fileDiff: nil))
    }
  }

  @Test func fileTappedSameFileIsNoOp() async {
    let store = TestStore(
      initialState: FileViewerFeature.State(
        worktreeURL: worktreeURL,
        files: .loaded([summary("a.swift")]),
        selectedPath: "a.swift",
        mode: .diff,
        content: .loaded(.init(rawText: nil, fileDiff: FileDiff(path: "a.swift", isBinary: false, hunks: [])))
      )
    ) {
      FileViewerFeature()
    }
    await store.send(.fileTapped("a.swift"))  // same path, same mode → no state change, no effect
  }

  @Test func contentFailedStoresMessage() async {
    let store = TestStore(
      initialState: FileViewerFeature.State(worktreeURL: worktreeURL, selectedPath: "a.swift", mode: .diff)
    ) {
      FileViewerFeature()
    } withDependencies: {
      $0.fileContent.read = { _ in throw GitClientError.commandFailed(command: "read", message: "") }
    }
    await store.send(.modeChanged(.source)) {
      $0.mode = .source
      $0.content = .loading
    }
    await store.receive(\.contentFailed) {
      $0.content = .failed("Git command failed: read")
    }
  }

  // MARK: - Live refresh (filesystem polling)

  @Test func refreshReloadsSelectedFileContent() async {
    let files = [summary("a.swift")]
    let oldDiff = FileDiff(path: "a.swift", isBinary: false, hunks: [])
    let newDiff = FileDiff(
      path: "a.swift",
      isBinary: false,
      hunks: [DiffHunk(header: "@@ -1,1 +1,1 @@", oldStart: 1, oldCount: 1, newStart: 1, newCount: 1, lines: [])]
    )
    let store = TestStore(
      initialState: FileViewerFeature.State(
        worktreeURL: worktreeURL,
        files: .loaded(files),
        selectedPath: "a.swift",
        mode: .diff,
        content: .loaded(.init(rawText: nil, fileDiff: oldDiff))
      )
    ) {
      FileViewerFeature()
    } withDependencies: {
      $0.gitClient.changedFiles = { _, _ in files }
      $0.gitClient.fileDiff = { _, _, _ in newDiff }
    }
    await store.send(.refresh)
    // File list unchanged + selection still valid → no state change here…
    await store.receive(\.filesRefreshed)
    // …but the selected file's diff did change, so the content swaps in.
    await store.receive(\.contentLoaded) {
      $0.content = .loaded(.init(rawText: nil, fileDiff: newDiff))
    }
  }

  @Test func refreshWithUnchangedDiffDoesNotMutateContent() async {
    let files = [summary("a.swift")]
    let diff = FileDiff(path: "a.swift", isBinary: false, hunks: [])
    let store = TestStore(
      initialState: FileViewerFeature.State(
        worktreeURL: worktreeURL,
        files: .loaded(files),
        selectedPath: "a.swift",
        mode: .diff,
        content: .loaded(.init(rawText: nil, fileDiff: diff))
      )
    ) {
      FileViewerFeature()
    } withDependencies: {
      $0.gitClient.changedFiles = { _, _ in files }
      $0.gitClient.fileDiff = { _, _, _ in diff }
    }
    await store.send(.refresh)
    await store.receive(\.filesRefreshed)
    // Same diff as current → dedup guard skips the mutation (no state change asserted).
    await store.receive(\.contentLoaded)
  }

  @Test func refreshReselectsWhenSelectedFileNoLongerChanged() async {
    let newDiff = FileDiff(path: "b.swift", isBinary: false, hunks: [])
    let bSummary = summary("b.swift")
    let store = TestStore(
      initialState: FileViewerFeature.State(
        worktreeURL: worktreeURL,
        files: .loaded([summary("a.swift")]),
        selectedPath: "a.swift",
        mode: .diff,
        content: .loaded(.init(rawText: nil, fileDiff: FileDiff(path: "a.swift", isBinary: false, hunks: [])))
      )
    ) {
      FileViewerFeature()
    } withDependencies: {
      $0.gitClient.changedFiles = { _, _ in [bSummary] }
      $0.gitClient.fileDiff = { _, _, _ in newDiff }
    }
    await store.send(.refresh)
    await store.receive(\.filesRefreshed) {
      $0.files = .loaded([bSummary])
      $0.selectedPath = "b.swift"  // a.swift no longer changed → fall back to first
    }
    await store.receive(\.contentLoaded) {
      $0.content = .loaded(.init(rawText: nil, fileDiff: newDiff))
    }
  }

  @Test func isMarkdownDetectsExtensions() {
    #expect(FileViewerFeature.isMarkdown("docs/readme.md"))
    #expect(FileViewerFeature.isMarkdown("A.MARKDOWN"))
    #expect(!FileViewerFeature.isMarkdown("src/main.swift"))
    #expect(!FileViewerFeature.isMarkdown("noext"))
  }

  // MARK: - openFile (terminal cmd-click entry point)

  @Test func openFileSwiftSetsSourceModeAndLoadsContent() async {
    let store = TestStore(initialState: FileViewerFeature.State(worktreeURL: worktreeURL)) {
      FileViewerFeature()
    } withDependencies: {
      $0.fileContent.read = { _ in "let x = 1\n" }
    }
    await store.send(.openFile(path: "src/main.swift", line: 42)) {
      $0.selectedPath = "src/main.swift"
      $0.targetLine = 42
      $0.mode = .source
      $0.content = .loading
    }
    await store.receive(\.contentLoaded) {
      $0.content = .loaded(FileViewerFeature.State.Loaded(rawText: "let x = 1\n", fileDiff: nil))
    }
  }

  @Test func openFileMarkdownSetsPreviewModeAndLoadsContent() async {
    let store = TestStore(initialState: FileViewerFeature.State(worktreeURL: worktreeURL)) {
      FileViewerFeature()
    } withDependencies: {
      $0.fileContent.read = { _ in "# Title\n" }
    }
    await store.send(.openFile(path: "docs/README.md", line: nil)) {
      $0.selectedPath = "docs/README.md"
      $0.targetLine = nil
      $0.mode = .preview
      $0.content = .loading
    }
    await store.receive(\.contentLoaded) {
      $0.content = .loaded(FileViewerFeature.State.Loaded(rawText: "# Title\n", fileDiff: nil))
    }
  }

  @Test func defaultModeReturnsPreviewForMarkdownSourceForOthers() {
    #expect(FileViewerFeature.defaultMode(forPath: "README.md") == .preview)
    #expect(FileViewerFeature.defaultMode(forPath: "NOTES.MARKDOWN") == .preview)
    #expect(FileViewerFeature.defaultMode(forPath: "src/main.swift") == .source)
    #expect(FileViewerFeature.defaultMode(forPath: "Makefile") == .source)
  }
}
