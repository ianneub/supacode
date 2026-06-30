import ComposableArchitecture
import Foundation

@Reducer
struct FileViewerFeature {
  @ObservableState
  struct State: Equatable {
    /// Real on-disk worktree directory (a worktree's `localWorkingDirectory`).
    var worktreeURL: URL
    var diffScope: DiffScope = .workingTreeVsBase
    var files: FileViewerLoadState<[DiffFileSummary]> = .idle
    var selectedPath: String?
    var mode: Mode = .diff
    var content: FileViewerLoadState<Loaded> = .idle

    enum Mode: Equatable, Sendable {
      case source
      case diff
      // `preview` (rendered markdown) arrives in Phase 3.
    }

    nonisolated struct Loaded: Equatable, Sendable {
      var rawText: String?
      var fileDiff: FileDiff?
    }
  }

  enum Action: Equatable {
    case task
    case filesLoaded([DiffFileSummary])
    case filesFailed(String)
    case fileTapped(String)
    case modeChanged(State.Mode)
    case contentLoaded(State.Loaded)
    case contentFailed(String)
    case closeButtonTapped
    case delegate(Delegate)

    @CasePathable
    enum Delegate: Equatable {
      case close
    }
  }

  nonisolated enum CancelID: Hashable, Sendable {
    case loadFiles
    case loadContent
  }

  @Dependency(GitClientDependency.self) var gitClient
  @Dependency(FileContentClient.self) var fileContent

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .task:
        state.files = .loading
        let url = state.worktreeURL
        let scope = state.diffScope
        return .run { send in
          do {
            let files = try await gitClient.changedFiles(url, scope)
            await send(.filesLoaded(files))
          } catch {
            await send(.filesFailed(error.localizedDescription))
          }
        }
        .cancellable(id: CancelID.loadFiles, cancelInFlight: true)

      case .filesLoaded(let files):
        state.files = .loaded(files)
        // Auto-select the first changed file in diff mode so the pane isn't empty.
        guard state.selectedPath == nil, let first = files.first?.newPath ?? files.first?.oldPath
        else { return .none }
        state.selectedPath = first
        state.mode = .diff
        return Self.loadContent(state: &state, gitClient: gitClient, fileContent: fileContent)

      case .filesFailed(let message):
        state.files = .failed(message)
        return .none

      case .fileTapped(let path):
        state.selectedPath = path
        state.mode = .diff
        return Self.loadContent(state: &state, gitClient: gitClient, fileContent: fileContent)

      case .modeChanged(let mode):
        guard state.mode != mode else { return .none }
        state.mode = mode
        return Self.loadContent(state: &state, gitClient: gitClient, fileContent: fileContent)

      case .contentLoaded(let loaded):
        state.content = .loaded(loaded)
        return .none

      case .contentFailed(let message):
        state.content = .failed(message)
        return .none

      case .closeButtonTapped:
        return .send(.delegate(.close))

      case .delegate:
        return .none
      }
    }
  }

  /// Kicks a cancellable load of `selectedPath`'s content for the current mode.
  /// Sets `content = .loading` and returns the effect; no-op when nothing is selected.
  private static func loadContent(
    state: inout State,
    gitClient: GitClientDependency,
    fileContent: FileContentClient
  ) -> Effect<Action> {
    guard let path = state.selectedPath else { return .none }
    state.content = .loading
    let url = state.worktreeURL
    let scope = state.diffScope
    let mode = state.mode
    return .run { send in
      do {
        switch mode {
        case .diff:
          let diff = try await gitClient.fileDiff(url, path, scope)
          await send(.contentLoaded(State.Loaded(rawText: nil, fileDiff: diff)))
        case .source:
          let text = try await fileContent.read(url.appending(path: path))
          await send(.contentLoaded(State.Loaded(rawText: text, fileDiff: nil)))
        }
      } catch {
        await send(.contentFailed(error.localizedDescription))
      }
    }
    .cancellable(id: CancelID.loadContent, cancelInFlight: true)
  }
}
