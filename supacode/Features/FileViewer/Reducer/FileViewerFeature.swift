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
    /// Line to scroll to after `openFile` sets the selected path. Carried for
    /// Phase 4; visual scroll-to-line in the content view is a follow-up task.
    var targetLine: Int?
    var mode: Mode = .diff
    var content: FileViewerLoadState<Loaded> = .idle

    enum Mode: Equatable, Sendable {
      case source
      case diff
      case preview  // rendered markdown
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
    /// A filesystem tick while the pane is open: re-check the changed-file list.
    case refresh
    /// Result of a `refresh` file-list reload (no loading flash, keeps selection).
    case filesRefreshed([DiffFileSummary])
    case fileTapped(String)
    /// Open a specific file (from a terminal cmd-click). Sets `selectedPath`,
    /// `targetLine`, and `mode` (markdown → preview, else source), then loads content.
    case openFile(path: String, line: Int?)
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
    case watch
  }

  @Dependency(GitClientDependency.self) var gitClient
  @Dependency(FileContentClient.self) var fileContent
  @Dependency(WorktreeFileChangeClient.self) var fileChanges

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .task:
        state.files = .loading
        let url = state.worktreeURL
        let scope = state.diffScope
        let ticks = fileChanges.ticks
        return .merge(
          .run { send in
            do {
              let files = try await gitClient.changedFiles(url, scope)
              await send(.filesLoaded(files))
            } catch {
              await send(.filesFailed(error.localizedDescription))
            }
          }
          .cancellable(id: CancelID.loadFiles, cancelInFlight: true),
          // Live-refresh the diff while the pane is open (the HEAD watcher misses
          // working-tree edits). Cancelled when the pane closes.
          .run { send in
            for await _ in ticks(url) {
              await send(.refresh)
            }
          }
          .cancellable(id: CancelID.watch, cancelInFlight: true)
        )

      case .filesLoaded(let files):
        state.files = .loaded(files)
        // Auto-select the first changed file in diff mode so the pane isn't empty.
        guard state.selectedPath == nil, let first = files.first?.id, !first.isEmpty else { return .none }
        state.selectedPath = first
        state.mode = .diff
        return Self.loadContent(state: &state, gitClient: gitClient, fileContent: fileContent)

      case .filesFailed(let message):
        state.files = .failed(message)
        return .none

      case .refresh:
        // Background re-check; reload the file list without a loading flash, then
        // re-resolve the selection in `filesRefreshed`.
        let url = state.worktreeURL
        let scope = state.diffScope
        return .run { send in
          if let files = try? await gitClient.changedFiles(url, scope) {
            await send(.filesRefreshed(files))
          }
          // Transient git error: keep showing the current diff, try again next tick.
        }
        .cancellable(id: CancelID.loadFiles, cancelInFlight: true)

      case .filesRefreshed(let files):
        if state.files != .loaded(files) {
          state.files = .loaded(files)
        }
        // Keep the current selection if it's still changed; otherwise fall back to
        // the first changed file (or clear when nothing is changed anymore).
        let selectionStillChanged = state.selectedPath.map { sel in files.contains { $0.id == sel } } ?? false
        if !selectionStillChanged {
          if let first = files.first?.id, !first.isEmpty {
            state.selectedPath = first
            if state.mode == .preview, !Self.isMarkdown(first) {
              state.mode = .source
            }
          } else {
            state.selectedPath = nil
            state.content = .idle
            return .none
          }
        }
        guard state.selectedPath != nil else { return .none }
        // Reload the selected file's content without a loading flash; `contentLoaded`
        // dedupes so an unchanged diff doesn't churn the view.
        return Self.contentEffect(state: state, gitClient: gitClient, fileContent: fileContent)

      case .fileTapped(let path):
        guard state.selectedPath != path else { return .none }  // same-file no-op
        state.selectedPath = path
        // Preserve the current mode, but preview is only valid for markdown — fall back to source.
        if state.mode == .preview, !Self.isMarkdown(path) {
          state.mode = .source
        }
        return Self.loadContent(state: &state, gitClient: gitClient, fileContent: fileContent)

      case .openFile(let path, let line):
        state.selectedPath = path
        state.targetLine = line
        state.mode = Self.defaultMode(forPath: path)
        return Self.loadContent(state: &state, gitClient: gitClient, fileContent: fileContent)

      case .modeChanged(let mode):
        guard state.mode != mode else { return .none }
        state.mode = mode
        return Self.loadContent(state: &state, gitClient: gitClient, fileContent: fileContent)

      case .contentLoaded(let loaded):
        // Dedupe so a poll that found no change doesn't re-render (which would
        // reset the diff's scroll position).
        guard state.content != .loaded(loaded) else { return .none }
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

  /// Markdown files (`.md` / `.markdown`, case-insensitive) support preview mode.
  static func isMarkdown(_ path: String) -> Bool {
    let lower = path.lowercased()
    return lower.hasSuffix(".md") || lower.hasSuffix(".markdown")
  }

  /// Default display mode for a path opened via cmd-click: preview for markdown, source for everything else.
  static func defaultMode(forPath path: String) -> State.Mode {
    isMarkdown(path) ? .preview : .source
  }

  /// Kicks a cancellable load of `selectedPath`'s content for the current mode.
  /// Sets `content = .loading` and returns the effect; no-op when nothing is selected.
  private static func loadContent(
    state: inout State,
    gitClient: GitClientDependency,
    fileContent: FileContentClient
  ) -> Effect<Action> {
    guard state.selectedPath != nil else { return .none }
    state.content = .loading
    return contentEffect(state: state, gitClient: gitClient, fileContent: fileContent)
  }

  /// The content-load effect alone, with no `.loading` transition — used by the
  /// background refresh so an unchanged poll doesn't flash a spinner. `.contentLoaded`
  /// dedupes the result against the current state.
  private static func contentEffect(
    state: State,
    gitClient: GitClientDependency,
    fileContent: FileContentClient
  ) -> Effect<Action> {
    guard let path = state.selectedPath else { return .none }
    let url = state.worktreeURL
    let scope = state.diffScope
    let mode = state.mode
    return .run { send in
      do {
        switch mode {
        case .diff:
          let diff = try await gitClient.fileDiff(url, path, scope)
          await send(.contentLoaded(State.Loaded(rawText: nil, fileDiff: diff)))
        case .source, .preview:
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
