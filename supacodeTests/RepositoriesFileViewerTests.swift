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
