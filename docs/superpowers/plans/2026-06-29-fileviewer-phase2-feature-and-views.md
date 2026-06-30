# FileViewer Phase 2 — Feature + Source/Diff Views + Collapsible Side-Pane Mount

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `FileViewerFeature` TCA feature (changed-file list + per-file unified diff + plain source view, with mode toggle and cancellable loads) and mount it as a collapsible side pane beside the terminal in `WorktreeDetailView`, driven by the Phase 1 diff data layer.

**Architecture:** A single `@Reducer FileViewerFeature` owns the pane: it loads the changed-file list via `@Dependency(\.gitClient).changedFiles`, loads a selected file's unified diff via `.fileDiff`, and loads plain source text via a new injectable `FileContentClient`. The feature is scoped as a non-`@Presents` optional child of `RepositoriesFeature` (the pane is persistent, not a modal). `WorktreeDetailView` swaps the bare terminal for a horizontal `SplitView { terminal } right: { FileViewerView }` when the pane is open. Views are dumb renderers over feature state.

**Tech Stack:** Swift 6 / TCA (swift-composable-architecture) / swift-dependencies / swift-testing / Tuist workspace / prebuilt GhosttyKit.

## Global Constraints

- Target macOS 26.0+, Swift 6.0. The module uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: types are MainActor-isolated unless annotated `nonisolated`. New value types crossing into `@Sendable` effect closures (e.g. `Loaded`, `FileViewerLoadState`) MUST be `nonisolated`/`Sendable` + `Equatable`. `CancelID` enums inside a `@MainActor` reducer MUST be `nonisolated enum CancelID: Hashable, Sendable`.
- Use `@ObservableState` for TCA feature state; `@Observable` for non-TCA stores; never `ObservableObject`. Mark `@Observable` classes `@MainActor`.
- Modern SwiftUI only: `foregroundStyle()`, `Button` over `onTapGesture()`, `NavigationStack`. No `GeometryReader` where `containerRelativeFrame()`/`visualEffect()` work.
- **Never use custom colors — system/semantic colors only** (`.green`, `.red`, `.secondary`, `.primary`, `Color.accentColor`, `Color(nsColor: .separatorColor)`). Use `.monospaced()` for code/diff text.
- Use `SupaLogger` for logging — never `print()`/`os.Logger`.
- Custom SwiftLint rule `store_state_mutation_in_views`: never mutate `store.*` in view files — send actions. `@State`/`@Shared` bindings in views are fine.
- Prefer `@Shared` directly in reducers/views for app storage; do not wrap `@Shared` in a new client.
- In tests never use `Task.sleep`; inject `@Dependency(\.continuousClock)` and drive a `TestClock` with `await clock.advance`.
- Buttons need tooltips (`.help(...)`) explaining the action + any hotkey.
- 2-space indent, 120-col, trailing commas mandatory; swiftlint strict. Run `make check` (and the lint commands below) before each commit. **Actually run lint** — Phase 1 missed `large_tuple` and `identifier_name` violations because lint wasn't run.
- After a task, the app must build. New diff functions added in Phase 1 are already available: `@Dependency(\.gitClient).changedFiles(URL, DiffScope)` and `.fileDiff(URL, String, DiffScope)`, plus models `DiffFileSummary`, `DiffFileStatus`, `FileDiff`, `DiffHunk`, `DiffLine`, `DiffScope` in `supacode/Clients/Git/`.

## Environment — build/test/lint incantations (this machine)

The Tuist workspace and GhosttyKit are already built. Use these EXACT commands (the bare `xcodebuild`/`make test` will fail — wrong toolchain / flaky metal preflight):

```bash
# Run a focused test class (build is incremental; run in BACKGROUND and poll a log file):
SUPACODE_SKIP_PREFLIGHT=1 DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer \
  xcodebuild test -workspace supacode.xcworkspace -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/CLASSNAME \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation -parallel-testing-enabled NO

# Build the app (for view-only tasks with no unit tests — confirms compilation):
SUPACODE_SKIP_PREFLIGHT=1 DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer make build-app

# Lint (does NOT need the xcframework; runs fast):
mise exec -- swiftlint lint --quiet <files...>
mise exec -- swift-format lint --configuration .swift-format.json <files...>
```

- swift-testing results show as `✔ Test ... passed` / `✔ Test run with N tests in 1 suite passed`, NOT the legacy "Executed 0 tests" line.
- Commit signing works (1Password); commit normally. Commit ONLY your task's files (no `git add .`).

---

## File Structure

| File | Responsibility |
| --- | --- |
| `supacode/Clients/Git/DiffModels.swift` (modify) | Task 1: drop unused `import Foundation`; remove redundant inner `nonisolated` on `DiffLine.Kind`. |
| `supacode/Clients/Git/UnifiedDiffParser.swift` (modify) | Task 1: drop unused import; nil-out `flush()` state; strip trailing `\r` (CRLF). |
| `supacode/Clients/Git/ChangedFilesParser.swift` (modify) | Task 1: drop unused import. |
| `supacodeTests/UnifiedDiffParserTests.swift` (modify) | Task 1: drop unused import; add CRLF test. |
| `supacodeTests/ChangedFilesParserTests.swift` (modify) | Task 1: drop unused import; add `.copied` test. |
| `supacode/Clients/FileContent/FileContentClient.swift` (create) | Task 2: injectable file-text reader (`read: @Sendable (URL) async throws -> String`). |
| `supacode/Features/FileViewer/Models/FileViewerLoadState.swift` (create) | Task 2: generic `idle/loading/loaded/failed` enum. |
| `supacode/Features/FileViewer/Reducer/FileViewerFeature.swift` (create) | Task 2: the pane reducer + state + actions + load effects. |
| `supacodeTests/FileViewerFeatureTests.swift` (create) | Task 2: TestStore reducer tests. |
| `supacode/Features/FileViewer/Views/DiffView.swift` (create) | Task 3: renders `[DiffHunk]` inline with gutters + system colors. |
| `supacode/Features/FileViewer/Views/SourceView.swift` (create) | Task 3: plain monospaced read-only text. |
| `supacode/Features/FileViewer/Views/DiffFileListView.swift` (create) | Task 4: changed-files list (status icon + `+x/-y`). |
| `supacode/Features/FileViewer/Views/FileViewerView.swift` (create) | Task 4: composes list + mode picker + Source/Diff. |
| `supacode/Features/Repositories/BusinessLogic/FileViewerPaneKey.swift` (create) | Task 5: `@Shared` keys (split ratio). |
| `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift` (modify) | Task 5: optional child state/action, `.ifLet`, toggle, close-on-worktree-change. |
| `supacode/Features/Repositories/Views/WorktreeDetailView.swift` (modify) | Task 5: collapsible `SplitView` mount + toolbar toggle button. |
| `supacodeTests/RepositoriesFileViewerTests.swift` (create) | Task 5: TestStore tests for toggle / close / worktree-change. |

---

## Task 1: Fold Phase-1 deferred cleanups

The final Phase-1 review deferred these Minors to Phase 2's first commit (avoid a churn PR). All low-risk; verified by the existing parser tests plus two new cases.

**Files:**
- Modify: `supacode/Clients/Git/DiffModels.swift`, `supacode/Clients/Git/UnifiedDiffParser.swift`, `supacode/Clients/Git/ChangedFilesParser.swift`
- Test: `supacodeTests/UnifiedDiffParserTests.swift`, `supacodeTests/ChangedFilesParserTests.swift`

**Interfaces:** No signature changes. `UnifiedDiffParser.parse(_:path:)` and `ChangedFilesParser.parse(nameStatus:numstat:untracked:)` keep their exact signatures.

- [ ] **Step 1: Write the new failing tests.**

In `supacodeTests/UnifiedDiffParserTests.swift`, add inside the struct:
```swift
  @Test func stripsCarriageReturnFromCRLFContent() {
    let raw = "@@ -1,1 +1,1 @@\r\n-old\r\n+new\r\n"
    let hunk = UnifiedDiffParser.parse(raw, path: "a").hunks[0]
    #expect(hunk.lines.map(\.kind) == [.deletion, .addition])
    #expect(hunk.lines[0].text == "old")
    #expect(hunk.lines[1].text == "new")
  }
```

In `supacodeTests/ChangedFilesParserTests.swift`, add inside the struct:
```swift
  @Test func parsesCopiedStatus() {
    let nameStatus = "C100\tsrc/orig.swift\tsrc/copy.swift\n"
    let numstat = "0\t0\tsrc/copy.swift\n"
    let result = ChangedFilesParser.parse(nameStatus: nameStatus, numstat: numstat, untracked: [])
    #expect(result.count == 1)
    #expect(result[0].status == .copied)
    #expect(result[0].oldPath == "src/orig.swift")
    #expect(result[0].newPath == "src/copy.swift")
  }
```

- [ ] **Step 2: Run both classes to verify the CRLF test fails (copied test already passes).**

Run (background + grep the log):
```bash
SUPACODE_SKIP_PREFLIGHT=1 DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer \
  xcodebuild test -workspace supacode.xcworkspace -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/UnifiedDiffParserTests -only-testing:supacodeTests/ChangedFilesParserTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation -parallel-testing-enabled NO
```
Expected: `stripsCarriageReturnFromCRLFContent` FAILS (text is `"old\r"` not `"old"`); `parsesCopiedStatus` PASSES (the `C` arm already exists). This proves the CRLF gap is real.

- [ ] **Step 3: Apply the CRLF fix in `UnifiedDiffParser.swift`.**

In `parse(_:path:)`, the line split currently is:
```swift
    let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
```
Replace with a CRLF-stripping split:
```swift
    let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.hasSuffix("\r") ? String($0.dropLast()) : String($0) }
```

- [ ] **Step 4: Nil out flush() state in `UnifiedDiffParser.swift`.**

At the end of the nested `flush()` function, after `pendingLines = []`, add:
```swift
      pendingHeader = nil
      pendingBounds = nil
```
(Makes the no-double-append guarantee local instead of incidental.)

- [ ] **Step 5: Remove redundant inner `nonisolated` and unused imports.**

In `supacode/Clients/Git/DiffModels.swift`: remove the inner `nonisolated` on `DiffLine.Kind` so it reads `enum Kind: Equatable, Sendable { case context, addition, deletion, noNewlineMarker }` (the parent `nonisolated struct DiffLine` already confers it). Then delete the top `import Foundation` line.
In `supacode/Clients/Git/UnifiedDiffParser.swift` and `supacode/Clients/Git/ChangedFilesParser.swift`: delete the top `import Foundation` line (both use only stdlib).
In `supacodeTests/UnifiedDiffParserTests.swift` and `supacodeTests/ChangedFilesParserTests.swift`: delete `import Foundation` (they use only `Testing` + stdlib).

> If the compiler reports `Foundation` is actually needed in any file (e.g. an `Int`/`String` API that pulls Foundation), keep that one import and note it in the report. The parsers are stdlib-only by design, so this should not happen.

- [ ] **Step 6: Run both test classes — all green.**

Same command as Step 2. Expected: all tests PASS including the new CRLF test (text now `"old"`/`"new"`).

- [ ] **Step 7: Lint.**
```bash
mise exec -- swiftlint lint --quiet supacode/Clients/Git/DiffModels.swift supacode/Clients/Git/UnifiedDiffParser.swift supacode/Clients/Git/ChangedFilesParser.swift supacodeTests/UnifiedDiffParserTests.swift supacodeTests/ChangedFilesParserTests.swift
mise exec -- swift-format lint --configuration .swift-format.json supacode/Clients/Git/DiffModels.swift supacode/Clients/Git/UnifiedDiffParser.swift supacode/Clients/Git/ChangedFilesParser.swift
```
Expected: clean.

- [ ] **Step 8: Commit.**
```bash
git add supacode/Clients/Git/DiffModels.swift supacode/Clients/Git/UnifiedDiffParser.swift supacode/Clients/Git/ChangedFilesParser.swift supacodeTests/UnifiedDiffParserTests.swift supacodeTests/ChangedFilesParserTests.swift
git commit -m "Fold Phase 1 review cleanups: CRLF strip, flush reset, drop unused imports, copied test"
```

---

## Task 2: FileContentClient + FileViewerLoadState + FileViewerFeature

**Files:**
- Create: `supacode/Clients/FileContent/FileContentClient.swift`
- Create: `supacode/Features/FileViewer/Models/FileViewerLoadState.swift`
- Create: `supacode/Features/FileViewer/Reducer/FileViewerFeature.swift`
- Test: `supacodeTests/FileViewerFeatureTests.swift`

**Interfaces:**
- Consumes: `@Dependency(\.gitClient).changedFiles`, `.fileDiff`; Phase 1 models `DiffFileSummary`, `FileDiff`, `DiffScope`.
- Produces:
  - `struct FileContentClient: Sendable { var read: @Sendable (URL) async throws -> String }` + `DependencyValues.fileContent`.
  - `enum FileViewerLoadState<Value: Equatable & Sendable>: Equatable, Sendable { case idle, loading, loaded(Value), failed(String) }`
  - `@Reducer struct FileViewerFeature` with `State`, `Action` (incl. `Delegate.close`), `Mode { source, diff }`, `Loaded { rawText, fileDiff }`.

- [ ] **Step 1: Create `FileContentClient`.**

Create `supacode/Clients/FileContent/FileContentClient.swift`:
```swift
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
```

- [ ] **Step 2: Create `FileViewerLoadState`.**

Create `supacode/Features/FileViewer/Models/FileViewerLoadState.swift`:
```swift
import Foundation

/// Generic async-load state for the file viewer's file list and file content.
nonisolated enum FileViewerLoadState<Value: Equatable & Sendable>: Equatable, Sendable {
  case idle
  case loading
  case loaded(Value)
  case failed(String)
}
```

- [ ] **Step 3: Write the failing reducer tests.**

Create `supacodeTests/FileViewerFeatureTests.swift`:
```swift
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
    struct Boom: Error {}
    let store = TestStore(initialState: FileViewerFeature.State(worktreeURL: worktreeURL)) {
      FileViewerFeature()
    } withDependencies: {
      $0.gitClient.changedFiles = { _, _ in throw Boom() }
    }
    await store.send(.task) { $0.files = .loading }
    await store.receive(\.filesFailed) {
      $0.files = .failed("The operation couldn’t be completed. (supacodeTests.FileViewerFeatureTests.(unknown context at $0).(unknown context).Boom error 1.)")
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
```

> The exact error string in `filesFailedStoresMessage` is brittle. When you run RED you will see the real `localizedDescription` for the thrown `Boom()` — copy that exact string into the expectation. If matching the string is awkward, instead assert with a custom-dump-free check by changing the test to use a `FileContentError`/`GitClientError` whose `errorDescription` is stable, OR assert `if case .failed = $0.files {} else { Issue.record("expected failed") }`. Pick the stable form; do not leave a guessed string.

- [ ] **Step 4: Run tests to verify they fail.**

Run with `-only-testing:supacodeTests/FileViewerFeatureTests`. Expected: compile failure — `FileViewerFeature` undefined.

- [ ] **Step 5: Implement `FileViewerFeature`.**

Create `supacode/Features/FileViewer/Reducer/FileViewerFeature.swift`:
```swift
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

    struct Loaded: Equatable, Sendable {
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

  @Dependency(\.gitClient) var gitClient
  @Dependency(\.fileContent) var fileContent

  var body: some ReducerOf<Self> {
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
```

> Note `loadContent` is a `private static func` taking `inout State` + the two dependency values (passed in because a static helper has no `@Dependency` access). This keeps the load logic DRY across `.filesLoaded` / `.fileTapped` / `.modeChanged` without a top-level free function.

- [ ] **Step 6: Run tests to verify they pass.**

Run with `-only-testing:supacodeTests/FileViewerFeatureTests`. Expected: all PASS. If the `filesFailedStoresMessage` string mismatches, paste the real `localizedDescription` from the failure output (per the Step 3 note) and re-run.

- [ ] **Step 7: Lint.**
```bash
mise exec -- swiftlint lint --quiet supacode/Clients/FileContent/FileContentClient.swift supacode/Features/FileViewer/Models/FileViewerLoadState.swift supacode/Features/FileViewer/Reducer/FileViewerFeature.swift supacodeTests/FileViewerFeatureTests.swift
mise exec -- swift-format lint --configuration .swift-format.json supacode/Clients/FileContent/FileContentClient.swift supacode/Features/FileViewer/Models/FileViewerLoadState.swift supacode/Features/FileViewer/Reducer/FileViewerFeature.swift
```

- [ ] **Step 8: Commit.**
```bash
git add supacode/Clients/FileContent/FileContentClient.swift supacode/Features/FileViewer/Models/FileViewerLoadState.swift supacode/Features/FileViewer/Reducer/FileViewerFeature.swift supacodeTests/FileViewerFeatureTests.swift
git commit -m "Add FileViewerFeature reducer with FileContentClient and load effects"
```

---

## Task 3: DiffView + SourceView

Pure SwiftUI views (no unit tests — verified by compilation + the Task 5 visual check). Render Phase 1 model values; system colors only.

**Files:**
- Create: `supacode/Features/FileViewer/Views/DiffView.swift`
- Create: `supacode/Features/FileViewer/Views/SourceView.swift`

**Interfaces:**
- Consumes: `FileDiff`, `DiffHunk`, `DiffLine` (Phase 1).
- Produces: `struct DiffView: View { let fileDiff: FileDiff }`, `struct SourceView: View { let text: String }`.

- [ ] **Step 1: Create `DiffView`.**

Create `supacode/Features/FileViewer/Views/DiffView.swift`:
```swift
import SwiftUI

/// Inline unified-diff renderer: old/new line-number gutters + add/delete/context
/// coloring from system semantic colors. Lazy so large diffs don't render at once.
struct DiffView: View {
  let fileDiff: FileDiff

  var body: some View {
    if fileDiff.isBinary {
      ContentUnavailableView("Binary file", systemImage: "doc.badge.gearshape")
    } else if fileDiff.hunks.isEmpty {
      ContentUnavailableView("No changes", systemImage: "equal")
    } else {
      ScrollView([.vertical, .horizontal]) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(Array(fileDiff.hunks.enumerated()), id: \.offset) { _, hunk in
            Text(hunk.header)
              .font(.body.monospaced())
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 2)
              .background(.quaternary)
            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
              DiffLineRow(line: line)
            }
          }
        }
        .padding(.vertical, 4)
      }
      .textSelection(.enabled)
    }
  }
}

private struct DiffLineRow: View {
  let line: DiffLine

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      gutter(line.oldNumber)
      gutter(line.newNumber)
      Text(prefix + line.text)
        .font(.body.monospaced())
        .foregroundStyle(textColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }
    .padding(.horizontal, 4)
    .background(rowBackground)
  }

  private func gutter(_ number: Int?) -> some View {
    Text(number.map(String.init) ?? "")
      .font(.body.monospaced())
      .foregroundStyle(.secondary)
      .frame(width: 44, alignment: .trailing)
      .padding(.trailing, 6)
  }

  private var prefix: String {
    switch line.kind {
    case .addition: "+ "
    case .deletion: "- "
    case .context: "  "
    case .noNewlineMarker: ""
    }
  }

  private var textColor: Color {
    switch line.kind {
    case .addition: .green
    case .deletion: .red
    case .context: .primary
    case .noNewlineMarker: .secondary
    }
  }

  private var rowBackground: Color {
    switch line.kind {
    case .addition: Color.green.opacity(0.12)
    case .deletion: Color.red.opacity(0.12)
    case .context, .noNewlineMarker: .clear
    }
  }
}
```

> `Color.green/.red` are system semantic colors (allowed); `.opacity()` tints the row band. The `.quaternary`/`.secondary`/`.primary` styles resolve under the `windowTintColorScheme` override already on the detail subtree.

- [ ] **Step 2: Create `SourceView`.**

Create `supacode/Features/FileViewer/Views/SourceView.swift`:
```swift
import SwiftUI

/// Plain, read-only, monospaced source rendering. Syntax highlighting is a
/// deliberate future enhancement (not this pass).
struct SourceView: View {
  let text: String

  var body: some View {
    ScrollView([.vertical, .horizontal]) {
      Text(text.isEmpty ? " " : text)
        .font(.body.monospaced())
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .padding(8)
    }
  }
}
```

- [ ] **Step 3: Build to confirm both views compile.**
```bash
SUPACODE_SKIP_PREFLIGHT=1 DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer make build-app
```
Expected: build succeeds.

- [ ] **Step 4: Lint.**
```bash
mise exec -- swiftlint lint --quiet supacode/Features/FileViewer/Views/DiffView.swift supacode/Features/FileViewer/Views/SourceView.swift
mise exec -- swift-format lint --configuration .swift-format.json supacode/Features/FileViewer/Views/DiffView.swift supacode/Features/FileViewer/Views/SourceView.swift
```

- [ ] **Step 5: Commit.**
```bash
git add supacode/Features/FileViewer/Views/DiffView.swift supacode/Features/FileViewer/Views/SourceView.swift
git commit -m "Add DiffView and SourceView renderers"
```

---

## Task 4: DiffFileListView + FileViewerView

**Files:**
- Create: `supacode/Features/FileViewer/Views/DiffFileListView.swift`
- Create: `supacode/Features/FileViewer/Views/FileViewerView.swift`

**Interfaces:**
- Consumes: `FileViewerFeature`, `DiffFileSummary`, `DiffFileStatus`, `FileViewerLoadState`, `DiffView`, `SourceView`.
- Produces: `struct DiffFileListView: View` (takes the list, selection, and an `onTap`), `struct FileViewerView: View { @Bindable var store: StoreOf<FileViewerFeature> }`.

- [ ] **Step 1: Create `DiffFileListView`.**

Create `supacode/Features/FileViewer/Views/DiffFileListView.swift`:
```swift
import SwiftUI

/// The changed-files list. Pure renderer: parent supplies the files, the
/// selected path, and a tap handler that drives the viewer.
struct DiffFileListView: View {
  let files: [DiffFileSummary]
  let selectedPath: String?
  let onTap: (String) -> Void

  var body: some View {
    List(files, id: \.id, selection: .constant(selectedPath)) { file in
      Button {
        onTap(file.id)
      } label: {
        HStack(spacing: 6) {
          Image(systemName: Self.symbol(for: file.status))
            .foregroundStyle(Self.color(for: file.status))
            .frame(width: 16)
          Text(Self.displayName(file))
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer(minLength: 8)
          if file.isBinary {
            Text("bin").font(.caption).foregroundStyle(.secondary)
          } else {
            Text("+\(file.added)").font(.caption.monospaced()).foregroundStyle(.green)
            Text("-\(file.removed)").font(.caption.monospaced()).foregroundStyle(.red)
          }
        }
      }
      .buttonStyle(.plain)
      .help(Self.displayName(file))
    }
    .listStyle(.sidebar)
  }

  private static func displayName(_ file: DiffFileSummary) -> String {
    switch file.status {
    case .renamed, .copied:
      "\(file.oldPath ?? "?") → \(file.newPath ?? "?")"
    default:
      file.newPath ?? file.oldPath ?? "?"
    }
  }

  private static func symbol(for status: DiffFileStatus) -> String {
    switch status {
    case .added: "plus.circle"
    case .modified: "pencil.circle"
    case .deleted: "minus.circle"
    case .renamed: "arrow.right.circle"
    case .copied: "doc.on.doc"
    case .untracked: "questionmark.circle"
    }
  }

  private static func color(for status: DiffFileStatus) -> Color {
    switch status {
    case .added, .untracked: .green
    case .modified, .renamed, .copied: .secondary
    case .deleted: .red
    }
  }
}
```

- [ ] **Step 2: Create `FileViewerView`.**

Create `supacode/Features/FileViewer/Views/FileViewerView.swift`:
```swift
import ComposableArchitecture
import SwiftUI

/// The side-pane root: changed-file list on top, the selected file's content
/// (Diff or Source) below, with a mode picker and a close button.
struct FileViewerView: View {
  @Bindable var store: StoreOf<FileViewerFeature>

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      fileList
      Divider()
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(.background)
    .task { store.send(.task) }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Picker("Mode", selection: Binding(get: { store.mode }, set: { store.send(.modeChanged($0)) })) {
        Text("Diff").tag(FileViewerFeature.State.Mode.diff)
        Text("Source").tag(FileViewerFeature.State.Mode.source)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(maxWidth: 180)
      .disabled(store.selectedPath == nil)
      Spacer()
      Button {
        store.send(.closeButtonTapped)
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.borderless)
      .help("Close the file viewer")
    }
    .padding(8)
  }

  @ViewBuilder private var fileList: some View {
    switch store.files {
    case .idle, .loading:
      ProgressView().frame(maxWidth: .infinity).frame(height: 120)
    case .loaded(let files):
      if files.isEmpty {
        ContentUnavailableView("No changed files", systemImage: "checkmark.circle")
          .frame(height: 120)
      } else {
        DiffFileListView(
          files: files,
          selectedPath: store.selectedPath,
          onTap: { store.send(.fileTapped($0)) }
        )
        .frame(height: 160)
      }
    case .failed(let message):
      ContentUnavailableView("Couldn’t load changes", systemImage: "exclamationmark.triangle", description: Text(message))
        .frame(height: 120)
    }
  }

  @ViewBuilder private var content: some View {
    switch store.content {
    case .idle:
      ContentUnavailableView("Select a file", systemImage: "doc.text")
    case .loading:
      ProgressView()
    case .loaded(let loaded):
      if let diff = loaded.fileDiff {
        DiffView(fileDiff: diff)
      } else if let text = loaded.rawText {
        SourceView(text: text)
      } else {
        ContentUnavailableView("Nothing to show", systemImage: "doc")
      }
    case .failed(let message):
      ContentUnavailableView("Couldn’t load file", systemImage: "exclamationmark.triangle", description: Text(message))
    }
  }
}
```

- [ ] **Step 3: Build to confirm compilation.**
```bash
SUPACODE_SKIP_PREFLIGHT=1 DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer make build-app
```

- [ ] **Step 4: Lint** (both files, both linters).

- [ ] **Step 5: Commit.**
```bash
git add supacode/Features/FileViewer/Views/DiffFileListView.swift supacode/Features/FileViewer/Views/FileViewerView.swift
git commit -m "Add DiffFileListView and composed FileViewerView"
```

---

## Task 5: Mount in RepositoriesFeature + WorktreeDetailView (collapsible side pane)

**Files:**
- Create: `supacode/Features/Repositories/BusinessLogic/FileViewerPaneKey.swift`
- Modify: `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift`
- Modify: `supacode/Features/Repositories/Views/WorktreeDetailView.swift`
- Test: `supacodeTests/RepositoriesFileViewerTests.swift`

**Interfaces:**
- Consumes: `FileViewerFeature`, `WorktreeDetailView`'s active-worktree branch, `SplitView`, `state.worktree(for:)`, `Worktree.localWorkingDirectory`.
- Produces (on `RepositoriesFeature`): `var fileViewer: FileViewerFeature.State?`, `case fileViewer(FileViewerFeature.Action)`, `case toggleFileViewer`; `@Shared(.fileViewerSplitRatio)` key.

- [ ] **Step 1: Create the `@Shared` ratio key.**

Create `supacode/Features/Repositories/BusinessLogic/FileViewerPaneKey.swift`:
```swift
import ComposableArchitecture
import Foundation

nonisolated extension SharedReaderKey where Self == AppStorageKey<Double>.Default {
  /// Persisted left-pane (terminal) fraction of the worktree-detail split, 0...1.
  static var fileViewerSplitRatio: Self {
    Self[.appStorage("fileViewerSplitRatio"), default: 0.6]
  }
}
```

- [ ] **Step 2: Write the failing reducer tests.**

Create `supacodeTests/RepositoriesFileViewerTests.swift`:
```swift
import ComposableArchitecture
import Foundation
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
}
```

> Use the existing test factories `makeWorktree`/`makeRepository`/`makeState` from `RepositoriesFeatureTests.swift` (same target — they are accessible). If `makeWorktree` produces a worktree whose `localWorkingDirectory` is `nil` (remote), adjust the factory call so the fixture is a local worktree (the default `/tmp/...` id is local). `exhaustivity = .off` keeps these tests focused on the file-viewer arms without asserting the sidebar/selection side effects that `makeState`-based sends trigger.

- [ ] **Step 3: Run to verify failure.**

Run `-only-testing:supacodeTests/RepositoriesFileViewerTests`. Expected: compile failure — `toggleFileViewer` / `fileViewer` not defined.

- [ ] **Step 4: Add child state + action to `RepositoriesFeature`.**

In `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift`, add to `State` near the other child-feature properties (after `@Presents var alert` ~line 184). NOTE: this is a NON-`@Presents` optional (persistent pane, not a modal):
```swift
    /// The file-viewer side pane for the selected worktree. `nil` = pane closed.
    var fileViewer: FileViewerFeature.State?
```

Add to `Action` near the other child cases (~line 426):
```swift
    case fileViewer(FileViewerFeature.Action)
    case toggleFileViewer
```

- [ ] **Step 5: Handle the new actions in the root `Reduce`.**

In the big root `Reduce`'s switch, add arms (place near other worktree-detail actions):
```swift
      case .toggleFileViewer:
        if state.fileViewer != nil {
          state.fileViewer = nil
          return .none
        }
        guard
          let worktree = state.worktree(for: state.selectedWorktreeID),
          let localURL = worktree.localWorkingDirectory
        else {
          // Folder/remote worktrees have no local diff surface — ignore.
          return .none
        }
        state.fileViewer = FileViewerFeature.State(worktreeURL: localURL)
        return .none

      case .fileViewer(.delegate(.close)):
        state.fileViewer = nil
        return .none

      case .fileViewer:
        return .none
```

Also close the pane when the selected worktree changes, so it never shows a stale worktree's files. Find the existing handler that sets `state.selection` on a worktree-selection change (search for `state.selection =` / a `.selectWorktree`-style action). In that handler, when the selection's worktree id changes, add:
```swift
        if state.fileViewer != nil, state.selectedWorktreeID != previouslySelectedID {
          state.fileViewer = nil
        }
```
> If pinpointing the selection-change site is ambiguous, instead add a guard at the top of the `.fileViewer(...)` non-close arm OR reset in the `.selectionChanged`/equivalent action. Name the exact action you hooked in your report. The invariant to preserve: `state.fileViewer?.worktreeURL` always matches the currently selected worktree's `localWorkingDirectory`, else `fileViewer` is `nil`.

- [ ] **Step 6: Compose the child reducer in `body`.**

In the operator chain after the root `Reduce` (near the other `.ifLet`s ~line 3916), add a non-presentation `ifLet`:
```swift
    .ifLet(\.fileViewer, action: \.fileViewer) {
      FileViewerFeature()
    }
```

- [ ] **Step 7: Run reducer tests — green.**

Run `-only-testing:supacodeTests/RepositoriesFileViewerTests`. Expected: PASS.

- [ ] **Step 8: Mount the collapsible SplitView in `WorktreeDetailView`.**

In `supacode/Features/Repositories/Views/WorktreeDetailView.swift`:

(a) Add the persisted ratio near the other `@Shared` at the top of the struct (~line 16):
```swift
  @Shared(.fileViewerSplitRatio) private var fileViewerSplitRatio: Double
```

(b) Replace the active-worktree branch body (lines 237-255, the `else if let selectedWorktree {` arm) so the terminal is wrapped in a SplitView when the pane is open. Keep `.id(selectedWorktree.id)` on the stable outer container:
```swift
      } else if let selectedWorktree {
        let shouldRunSetupScript = selectedSlice?.lifecycle == .pending
        let shouldFocusTerminal = repositories.shouldFocusTerminal(for: selectedWorktree.id)
        let terminal = WorktreeTerminalTabsView(
          worktree: selectedWorktree,
          manager: terminalManager,
          terminalsStore: store.scope(state: \.terminals, action: \.terminals),
          shouldRunSetupScript: shouldRunSetupScript,
          forceAutoFocus: shouldFocusTerminal,
          createTab: { store.send(.newTerminal) }
        )
        Group {
          if let fileViewerStore = store.scope(
            state: \.repositories.fileViewer,
            action: \.repositories.fileViewer
          ) {
            SplitView(
              .horizontal,
              Binding(
                get: { CGFloat(fileViewerSplitRatio) },
                set: { newValue in $fileViewerSplitRatio.withLock { $0 = Double(newValue) } }
              ),
              dividerColor: Color(nsColor: .separatorColor),
              left: { terminal },
              right: { FileViewerView(store: fileViewerStore) },
              onEqualize: { $fileViewerSplitRatio.withLock { $0 = 0.6 } }
            )
          } else {
            terminal
          }
        }
        .id(selectedWorktree.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .bottom)
        .animation(.easeInOut(duration: 0.2), value: store.repositories.fileViewer != nil)
        .onAppear {
          if shouldFocusTerminal {
            store.send(.repositories(.consumeTerminalFocus(selectedWorktree.id)))
          }
        }
      }
```
The split `Binding` writes the ratio through `@Shared` via `withLock`; the get reads it back as `CGFloat`.

(c) Add a toolbar toggle button. In the existing `.toolbar` block (lines 74-122), add a `ToolbarItem` matching the surrounding items' style, gated to a selected local git worktree:
```swift
        ToolbarItem(placement: .primaryAction) {
          Button {
            store.send(.repositories(.toggleFileViewer))
          } label: {
            Image(systemName: "sidebar.squares.right")
          }
          .help("Show changed files and diffs (side pane)")
          .disabled(store.repositories.worktree(for: store.repositories.selectedWorktreeID)?.localWorkingDirectory == nil)
        }
```
> Match the exact `ToolbarItem` placement/style of the adjacent items in that block — read the surrounding toolbar code and slot this in consistently. If `selectedWorktreeID`/`worktree(for:)` aren't reachable as written from the view, gate instead on `store.repositories.selection?.worktreeID != nil`.

- [ ] **Step 9: Build the app.**
```bash
SUPACODE_SKIP_PREFLIGHT=1 DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer make build-app
```
Expected: build succeeds.

- [ ] **Step 10: Lint all modified/created files.**
```bash
mise exec -- swiftlint lint --quiet supacode/Features/Repositories/BusinessLogic/FileViewerPaneKey.swift supacode/Features/Repositories/Reducer/RepositoriesFeature.swift supacode/Features/Repositories/Views/WorktreeDetailView.swift supacodeTests/RepositoriesFileViewerTests.swift
mise exec -- swift-format lint --configuration .swift-format.json supacode/Features/Repositories/BusinessLogic/FileViewerPaneKey.swift supacode/Features/Repositories/Views/WorktreeDetailView.swift
```

- [ ] **Step 11: Full regression of the touched reducers.**
```bash
SUPACODE_SKIP_PREFLIGHT=1 DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer \
  xcodebuild test -workspace supacode.xcworkspace -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/FileViewerFeatureTests -only-testing:supacodeTests/RepositoriesFileViewerTests \
  -only-testing:supacodeTests/RepositoriesFeatureTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation -parallel-testing-enabled NO
```
Expected: all green (RepositoriesFeatureTests confirms the additions didn't regress the parent).

- [ ] **Step 12: Commit.**
```bash
git add supacode/Features/Repositories/BusinessLogic/FileViewerPaneKey.swift supacode/Features/Repositories/Reducer/RepositoriesFeature.swift supacode/Features/Repositories/Views/WorktreeDetailView.swift supacodeTests/RepositoriesFileViewerTests.swift
git commit -m "Mount FileViewer as collapsible side pane in worktree detail"
```

---

## Manual verification (after Task 5)

Run the app, select a git worktree with uncommitted changes, click the toolbar "Show changed files" button:
- Pane slides in beside the terminal; changed files list populates; first file's diff auto-renders.
- Click another file → its diff renders. Toggle Source → plain monospaced file text. Toggle Diff → unified diff.
- Drag the divider → terminal/viewer resize; ratio persists across relaunch. Double-click divider → resets to 0.6.
- Click ✕ (or the toolbar button again) → pane collapses, terminal returns full-width.
- Switch worktrees → pane closes (no stale files).
- Verify add/delete coloring and gutters in both light and dark.

---

## Self-Review (completed during planning)

- **Spec coverage (design §4):** `FileViewerFeature` reducer/state + mode toggle ✅ (Task 2); load via gitClient (diff) + file-read dependency (source) + cancellation ✅ (Task 2); `SourceView` plain monospaced ✅ (Task 3); `DiffView` LazyVStack + gutters + theme(system) colors ✅ (Task 3); `DiffFileListView` status icon + `+x/-y` ✅ (Task 4); mount as collapsible side pane via `SplitView` in `WorktreeDetailView`, child-scoped from `RepositoriesFeature` ✅ (Task 5). Preview/markdown mode + mode-by-extension defaulting are explicitly Phase 3 (the `Mode` enum is `source`/`diff` only here, with a comment marking where `preview` lands). Terminal cmd-click is Phase 4 (the feature's `fileTapped`/load path is the seam Phase 4's `openFile` will reuse).
- **Type consistency:** `FileViewerFeature.State.Mode` (`source`/`diff`), `State.Loaded` (`rawText`/`fileDiff`), `FileViewerLoadState`, and the `.task`/`.filesLoaded`/`.fileTapped`/`.modeChanged`/`.contentLoaded`/`.delegate(.close)` actions are used identically across the reducer, its tests, `FileViewerView`, and the parent wiring.
- **Placeholder scan:** no TBD/TODO; all code is directly transcribable. One intentional test-data hazard is flagged with its fix inline: the brittle `localizedDescription` expectation in `filesFailedStoresMessage` — the implementer pastes the real string seen at RED, or switches to the `if case .failed` form given as the alternative. The selection-change hook in Step 5 is the one site I could not pin to an exact line (I don't have the selection-action name); the plan states the invariant to preserve and asks the implementer to name the action they hooked.
- **Isolation:** `FileViewerLoadState` is `nonisolated`/`Sendable`; `CancelID` is `nonisolated enum … Hashable, Sendable`; `Loaded` is `Sendable` — all required under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` because they cross `@Sendable` effect boundaries.
- **Known follow-ups (not this phase):** pane stays open across worktree switches (currently closes — simpler/safe); syntax highlighting; markdown preview (Phase 3); terminal cmd-click (Phase 4); thread one `DiffScope` through both calls and prefer `fileDiff.isBinary` (already honored — the list shows `bin` and `DiffView` handles `isBinary`).

---

## Next phases (separate plans)
- **Phase 3:** MarkdownUI dependency (`Tuist/Package.swift` + `Project.swift`) + `MarkdownPreviewView`; add `.preview` to `Mode`; mode-by-extension defaulting (`.md`/`.markdown` → preview); theming.
- **Phase 4:** ghostty `RepeatableLink.parseCLI` patch + `link` config line + bridge resolve/validate/route + `onOpenWorktreeFile` callback → a new `FileViewerFeature` external-open action (reuses the Task 2 load path) + auto-open the pane.
