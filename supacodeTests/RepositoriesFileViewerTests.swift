import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Testing

@testable import supacode

@MainActor
struct RepositoriesFileViewerTests {
  @Test func toggleOpensViewerForSelectedLocalWorktree() async {
    let worktree = makeWorktree(id: "/tmp/repo/main", name: "main")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    var initial = makeState(repositories: [repository])
    initial.selection = .worktree(worktree.id)
    let store = TestStore(initialState: initial) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.gitClient.changedFiles = { _, _ in [] }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.toggleFileViewer) {
      $0.fileViewer = FileViewerFeature.State(worktreeURL: worktree.localWorkingDirectory!)
    }
    await store.send(.toggleFileViewer) {
      $0.fileViewer = nil
    }
  }

  @Test func selectionChangedClosesFileViewer() async {
    let worktreeA = makeWorktree(id: "/tmp/repo/main", name: "main")
    let worktreeB = makeWorktree(id: "/tmp/repo/feature", name: "feature")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktreeA, worktreeB])
    var initial = makeState(repositories: [repository])
    initial.selection = .worktree(worktreeA.id)
    initial.fileViewer = FileViewerFeature.State(worktreeURL: worktreeA.localWorkingDirectory!)
    let store = TestStore(initialState: initial) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.selectionChanged([.worktree(worktreeB.id)], focusTerminal: false)) {
      $0.fileViewer = nil
    }
  }

  @Test func worktreeHistoryBackClosesFileViewer() async {
    let worktreeA = makeWorktree(id: "/tmp/repo/main", name: "main")
    let worktreeB = makeWorktree(id: "/tmp/repo/feature", name: "feature")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktreeA, worktreeB])
    var initial = makeState(repositories: [repository])
    initial.selection = .worktree(worktreeB.id)
    initial.worktreeHistoryBackStack = [worktreeA.id]
    initial.fileViewer = FileViewerFeature.State(worktreeURL: worktreeB.localWorkingDirectory!)
    let store = TestStore(initialState: initial) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.worktreeHistoryBack) {
      $0.fileViewer = nil
    }
  }

  @Test func worktreeHistoryForwardClosesFileViewer() async {
    let worktreeA = makeWorktree(id: "/tmp/repo/main", name: "main")
    let worktreeB = makeWorktree(id: "/tmp/repo/feature", name: "feature")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktreeA, worktreeB])
    var initial = makeState(repositories: [repository])
    initial.selection = .worktree(worktreeA.id)
    initial.worktreeHistoryForwardStack = [worktreeB.id]
    initial.fileViewer = FileViewerFeature.State(worktreeURL: worktreeA.localWorkingDirectory!)
    let store = TestStore(initialState: initial) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.worktreeHistoryForward) {
      $0.fileViewer = nil
    }
  }

  @Test func delegateCloseDismissesViewer() async {
    let worktree = makeWorktree(id: "/tmp/repo/main", name: "main")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    var initial = makeState(repositories: [repository])
    initial.selection = .worktree(worktree.id)
    initial.fileViewer = FileViewerFeature.State(worktreeURL: worktree.localWorkingDirectory!)
    let store = TestStore(initialState: initial) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.fileViewer(.delegate(.close))) {
      $0.fileViewer = nil
    }
  }

  @Test func openFileInViewerCreatesPaneWhenAbsent() async {
    let worktree = makeWorktree(id: "/tmp/repo/main", name: "main")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    var initial = makeState(repositories: [repository])
    initial.selection = .worktree(worktree.id)
    let store = TestStore(initialState: initial) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.fileContent.read = { _ in "let x = 1\n" }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.openFileInViewer(worktreeID: worktree.id, path: "src/main.swift", line: 10)) {
      $0.fileViewer = FileViewerFeature.State(worktreeURL: worktree.localWorkingDirectory!)
    }
    await store.receive(\.fileViewer.openFile) {
      $0.fileViewer?.selectedPath = "src/main.swift"
      $0.fileViewer?.targetLine = 10
      $0.fileViewer?.mode = .source
      $0.fileViewer?.content = .loading
    }
    await store.receive(\.fileViewer.contentLoaded) {
      $0.fileViewer?.content = .loaded(FileViewerFeature.State.Loaded(rawText: "let x = 1\n", fileDiff: nil))
    }
  }

  @Test func openFileInViewerReplacesPaneForDifferentWorktree() async {
    let worktreeA = makeWorktree(id: "/tmp/repo/main", name: "main")
    let worktreeB = makeWorktree(id: "/tmp/repo/feature", name: "feature")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktreeA, worktreeB])
    var initial = makeState(repositories: [repository])
    initial.selection = .worktree(worktreeA.id)
    // Pane is open for worktreeA.
    initial.fileViewer = FileViewerFeature.State(worktreeURL: worktreeA.localWorkingDirectory!)
    let store = TestStore(initialState: initial) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.fileContent.read = { _ in "# Feature\n" }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    // cmd-click in worktreeB terminal → pane re-created for worktreeB.
    await store.send(.openFileInViewer(worktreeID: worktreeB.id, path: "docs/NOTES.md", line: nil)) {
      $0.fileViewer = FileViewerFeature.State(worktreeURL: worktreeB.localWorkingDirectory!)
    }
    await store.receive(\.fileViewer.openFile) {
      $0.fileViewer?.selectedPath = "docs/NOTES.md"
      $0.fileViewer?.targetLine = nil
      $0.fileViewer?.mode = .preview
      $0.fileViewer?.content = .loading
    }
    await store.receive(\.fileViewer.contentLoaded) {
      $0.fileViewer?.content = .loaded(FileViewerFeature.State.Loaded(rawText: "# Feature\n", fileDiff: nil))
    }
  }

  // MARK: - Factories (mirrors the private helpers in RepositoriesFeatureTests)

  private func makeWorktree(
    id: String,
    name: String,
    repoRoot: String = "/tmp/repo"
  ) -> Worktree {
    Worktree(
      id: WorktreeID(id),
      name: name,
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: id),
      repositoryRootURL: URL(fileURLWithPath: repoRoot),
      createdAt: nil
    )
  }

  private func makeRepository(
    id: String,
    name: String = "repo",
    worktrees: [Worktree]
  ) -> Repository {
    Repository(
      id: RepositoryID(id),
      rootURL: URL(fileURLWithPath: id),
      name: name,
      worktrees: IdentifiedArray(uniqueElements: worktrees)
    )
  }

  private func makeState(repositories: [Repository]) -> RepositoriesFeature.State {
    var state = RepositoriesFeature.State()
    state.repositories = IdentifiedArray(uniqueElements: repositories)
    state.repositoryRoots = repositories.map(\.rootURL)
    return state
  }
}
