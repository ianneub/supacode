# FileViewer Phase 3 — Markdown Preview (MarkdownUI)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a rendered-markdown `preview` mode to the FileViewer: pull in the MarkdownUI Swift package, add a `.preview` case to `FileViewerFeature.State.Mode`, render the file's text via `MarkdownPreviewView`, and expose a Preview toggle for markdown files.

**Architecture:** `.preview` reuses the existing source-text load path (`fileContent.read` → `Loaded.rawText`); the data layer doesn't change shape. The *view* disambiguates preview-vs-source on `store.mode` (the content view currently keys off which `Loaded` optional is set, so it gains a mode-aware branch). `MarkdownPreviewView` renders `rawText` with MarkdownUI's `Markdown(_:)`, themed to the system color scheme. The Preview option appears only for markdown files; non-markdown files keep Diff/Source.

**Tech Stack:** Swift 6 / TCA / **MarkdownUI (gonzalezreal/swift-markdown-ui)** via Tuist / swift-testing / prebuilt GhosttyKit.

## Global Constraints

- Target macOS 26.0+, Swift 6.0, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (use `@Dependency(Type.self)`, `nonisolated` on Sendable value types crossing effect boundaries, `some Reducer<State, Action>`).
- Never use custom colors — system/semantic colors only; map MarkdownUI theming to the environment `colorScheme`. `.monospaced()` for code.
- `@ObservableState`/`@Observable` (never `ObservableObject`); custom lint rule `store_state_mutation_in_views` (no `store.*` writes in views — send actions / `@Shared` bindings). Buttons need `.help(...)`. Prefer Swift-native APIs; no top-level free functions.
- 2-space indent, 120-col, trailing commas; swiftlint strict (watch `large_tuple`, `identifier_name`, `accessibility_label_for_image`). **Actually run lint.**
- New SPM packages go in BOTH `Tuist/Package.swift` (pinned `.package(url:, exact:)`) AND `Project.swift` (`.external(name:)` in `appDependencies`), then `tuist install` + regenerate.

## Environment — build/test/lint incantations (this machine)

Commit signing is OFF locally (overnight headless run) — `git commit` normally (unsigned by design; user re-signs later). The Tuist workspace + GhosttyKit are already built. After Task 1 adds a package, the workspace must be regenerated.

```bash
# Install new SPM deps + regenerate the workspace (Task 1 only; needs network for the fetch):
mise exec -- tuist install
mise exec -- tuist generate --no-open

# Focused test class (build incremental; run in BACKGROUND + poll a log, or redirect+grep):
SUPACODE_SKIP_PREFLIGHT=1 DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer \
  xcodebuild test -workspace supacode.xcworkspace -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/CLASSNAME \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation -parallel-testing-enabled NO

# App build (view-only tasks):
SUPACODE_SKIP_PREFLIGHT=1 DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer make build-app

# Lint:
mise exec -- swiftlint lint --quiet <files...>
mise exec -- swift-format lint --configuration .swift-format.json <files...>
```
swift-testing GREEN = `✔ Test run with N tests in 1 suite passed` (ignore legacy "Executed 0 tests").

## Scope note (refinement of design §5/§11.3)
Phase 3 delivers the Preview **mode + rendering + manual toggle** (Preview appears for markdown files). **Mode-by-extension auto-defaulting** (open a `.md` straight into preview) is deferred to **Phase 4**, where the cmd-click "open this file" flow exists — in the diff-pane flow a file opens in Diff (you opened the pane to see changes). Phase 3 adds the pure `isMarkdown(_:)` helper that Phase 4 will build its `defaultMode(forPath:)` on.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `Tuist/Package.swift` (modify) | Add the MarkdownUI `.package(url:, exact:)` pin. |
| `Project.swift` (modify) | Add `.external(name: "MarkdownUI")` to `appDependencies`. |
| `supacode/Features/FileViewer/Reducer/FileViewerFeature.swift` (modify) | Add `.preview` to `Mode`; `.preview` arm in `loadContent`; `isMarkdown(_:)`; fix `fileTapped` mode handling; auto-select via `.id`; same-file no-op guard. |
| `supacodeTests/FileViewerFeatureTests.swift` (modify) | Tests: preview load, fileTapped mode-preserve + preview-validity fallback, contentFailed. |
| `supacode/Features/FileViewer/Views/MarkdownPreviewView.swift` (create) | Renders `rawText` via MarkdownUI, themed to system scheme. |
| `supacode/Features/FileViewer/Views/FileViewerView.swift` (modify) | Preview picker tag for markdown files; content switch branches on `store.mode`. |

---

## Task 1: Add the MarkdownUI dependency

**Files:** Modify `Tuist/Package.swift`, `Project.swift`.

**Interfaces:** Produces a linkable `import MarkdownUI` in the `supacode` app target.

- [ ] **Step 1: Add the package pin to `Tuist/Package.swift`.**

In the `dependencies:` array (alongside the existing `.package(url:..., exact:)` entries), add:
```swift
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1"),
```
> `2.4.1` is the intended pin. If `tuist install` (Step 3) fails to resolve it against this toolchain, bump to the newest tagged version that resolves cleanly and note the version used. Do NOT use a range — the file convention is `exact:`.

- [ ] **Step 2: Link it to the app target in `Project.swift`.**

In the `appDependencies` array, add (keep alphabetical-ish ordering with the other `.external` entries):
```swift
  .external(name: "MarkdownUI"),
```
> `MarkdownUI` is the SPM **product** name of swift-markdown-ui (distinct from the repo name). After Step 3 resolves the package, CONFIRM the product name from `Tuist/.build/checkouts/swift-markdown-ui/Package.swift` (look for `.library(name: ...)`); if it differs, use the real product name in `.external(name:)`.

- [ ] **Step 3: Install + regenerate.**
```bash
mise exec -- tuist install
mise exec -- tuist generate --no-open
```
Expected: install resolves swift-markdown-ui (+ its transitive deps, e.g. swift-cmark) and generation succeeds (`supacode.xcworkspace` rewritten). If install can't reach the network or fails to resolve, STOP and report BLOCKED with the exact error — do not hand-edit resolved files.

- [ ] **Step 4: Verify it links — add a temporary import probe and build.**

Append a throwaway line at the very bottom of `supacode/Features/FileViewer/Views/MarkdownPreviewView.swift`? No — that file doesn't exist yet. Instead, verify by building after Task 3 imports it. For Task 1's own verification, confirm resolution only:
```bash
mise exec -- tuist generate --no-open && echo "GENERATION OK"
grep -R "swift-markdown-ui" Tuist/Package.resolved | head
```
Expected: `GENERATION OK` and a `Package.resolved` entry for swift-markdown-ui. (The real link check happens in Task 3 when `import MarkdownUI` is used; if you prefer, you may create `MarkdownPreviewView.swift` here as a stub `import MarkdownUI` + empty `struct` and `make build-app`, then expand it in Task 3 — either order is fine, but commit the dependency wiring in this task.)

- [ ] **Step 5: Lint (manifest files are not Swift-source-linted, skip swiftlint; just confirm no stray edits).** Commit.
```bash
git add Tuist/Package.swift Tuist/Package.resolved Project.swift
git commit -m "Add MarkdownUI dependency via Tuist"
```
> `Package.resolved` records the resolved version — commit it so the pin is reproducible. Do NOT `git add .` (the regenerated `.xcworkspace`/`.xcodeproj` are gitignored).

---

## Task 2: `.preview` mode + reducer wiring + folded Phase-2 Minors

**Files:** Modify `supacode/Features/FileViewer/Reducer/FileViewerFeature.swift`; Test `supacodeTests/FileViewerFeatureTests.swift`.

**Interfaces:**
- Produces: `FileViewerFeature.State.Mode.preview`; `static func isMarkdown(_ path: String) -> Bool`.
- The `.preview` load reuses `fileContent.read` → `Loaded.rawText` (same as `.source`).

- [ ] **Step 1: Write the failing tests.**

Add to `supacodeTests/FileViewerFeatureTests.swift` (inside the struct):
```swift
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
      initialState: FileViewerFeature.State(worktreeURL: worktreeURL, selectedPath: "a.swift", mode: .source)
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

  @Test func isMarkdownDetectsExtensions() {
    #expect(FileViewerFeature.isMarkdown("docs/readme.md"))
    #expect(FileViewerFeature.isMarkdown("A.MARKDOWN"))
    #expect(!FileViewerFeature.isMarkdown("src/main.swift"))
    #expect(!FileViewerFeature.isMarkdown("noext"))
  }
```
> The existing `modeChangedToSourceReadsFileText` test sends `.modeChanged(.source)` from `mode: .diff` — unchanged. If folding the `fileTapped` mode-preserve change breaks the existing `fileTappedLoadsDiff` test (which asserted `mode = .diff` after tap), update that test: `fileTapped` now PRESERVES mode. Since that test starts at the default `mode = .diff` and taps with mode `.diff`, the expectation `$0.mode = .diff` still holds (no change) — but the same-file guard does not apply there (different path), so it still loads. Re-run it to confirm.

- [ ] **Step 2: Run tests → RED.** Run with `-only-testing:supacodeTests/FileViewerFeatureTests`. Expected: compile failure (`.preview`/`isMarkdown` undefined) or assertion failures.

- [ ] **Step 3: Add `.preview` to `Mode` and the `isMarkdown` helper.**

In `FileViewerFeature.State.Mode`:
```swift
    enum Mode: Equatable, Sendable {
      case source
      case diff
      case preview  // rendered markdown
    }
```

Add a static helper on `FileViewerFeature` (near `loadContent`):
```swift
  /// Markdown files (`.md` / `.markdown`, case-insensitive) support preview mode.
  static func isMarkdown(_ path: String) -> Bool {
    let lower = path.lowercased()
    return lower.hasSuffix(".md") || lower.hasSuffix(".markdown")
  }
```

- [ ] **Step 4: Add the `.preview` arm to `loadContent`.**

In the `loadContent` effect's `switch mode`, add `.preview` alongside `.source` (both read file text into `rawText`):
```swift
        case .source, .preview:
          let text = try await fileContent.read(url.appending(path: path))
          await send(.contentLoaded(State.Loaded(rawText: text, fileDiff: nil)))
```
(Leave the `.diff` arm unchanged.)

- [ ] **Step 5: Fix `fileTapped` — preserve mode with preview-validity guard + same-file no-op + `.id` auto-select.**

Replace the `fileTapped` arm:
```swift
      case .fileTapped(let path):
        guard state.selectedPath != path else { return .none }  // same-file no-op
        state.selectedPath = path
        // Preserve the current mode, but preview is only valid for markdown — fall back to source.
        if state.mode == .preview, !Self.isMarkdown(path) {
          state.mode = .source
        }
        return Self.loadContent(state: &state, gitClient: gitClient, fileContent: fileContent)
```

And in the `filesLoaded` auto-select, force the initial `.diff` and use the list's `id` for the selection key:
```swift
      case .filesLoaded(let files):
        state.files = .loaded(files)
        guard state.selectedPath == nil, let first = files.first?.id, !first.isEmpty else { return .none }
        state.selectedPath = first
        state.mode = .diff
        return Self.loadContent(state: &state, gitClient: gitClient, fileContent: fileContent)
```
> `DiffFileSummary.id` is `newPath ?? oldPath ?? ""`; the `!first.isEmpty` guard rejects a degenerate empty id (matching the prior two-chain behavior) — this is the single-source-of-truth fix for the Phase-2 Minor.

- [ ] **Step 6: Run tests → GREEN** (`-only-testing:supacodeTests/FileViewerFeatureTests`). All pass, including the updated existing tests.

- [ ] **Step 7: Lint.**
```bash
mise exec -- swiftlint lint --quiet supacode/Features/FileViewer/Reducer/FileViewerFeature.swift supacodeTests/FileViewerFeatureTests.swift
mise exec -- swift-format lint --configuration .swift-format.json supacode/Features/FileViewer/Reducer/FileViewerFeature.swift
```

- [ ] **Step 8: Commit.**
```bash
git add supacode/Features/FileViewer/Reducer/FileViewerFeature.swift supacodeTests/FileViewerFeatureTests.swift
git commit -m "Add preview mode to FileViewerFeature; preserve mode on file tap"
```

---

## Task 3: MarkdownPreviewView + FileViewerView wiring

**Files:** Create `supacode/Features/FileViewer/Views/MarkdownPreviewView.swift`; Modify `supacode/Features/FileViewer/Views/FileViewerView.swift`.

**Interfaces:** Consumes `MarkdownUI`, `FileViewerFeature.State.Mode.preview`, `FileViewerFeature.isMarkdown`. Produces `struct MarkdownPreviewView: View { let text: String }`.

- [ ] **Step 1: Create `MarkdownPreviewView`.**

Create `supacode/Features/FileViewer/Views/MarkdownPreviewView.swift`:
```swift
import MarkdownUI
import SwiftUI

/// Renders markdown source text as formatted, themed content. Read-only.
struct MarkdownPreviewView: View {
  let text: String

  var body: some View {
    ScrollView {
      Markdown(text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .padding(12)
    }
  }
}
```
> `Markdown(_:)` is MarkdownUI's view initializer taking a markdown `String`. If the resolved MarkdownUI version's initializer differs (e.g. requires `Markdown { text }` content-builder form), adjust minimally to the resolved API and note it. Default theming adapts to the environment `colorScheme` (the detail subtree already sets it via `windowTintColorScheme`). Custom theme-to-system-color mapping is optional polish — do NOT add a custom `Theme` unless the default renders unreadably; if you do, map only to system colors (no custom hex).

- [ ] **Step 2: Wire Preview into `FileViewerView`.**

(a) In the header `Picker`, show a Preview tag only for markdown files. Replace the Picker block:
```swift
      Picker("Mode", selection: Binding(get: { store.mode }, set: { store.send(.modeChanged($0)) })) {
        Text("Diff").tag(FileViewerFeature.State.Mode.diff)
        Text("Source").tag(FileViewerFeature.State.Mode.source)
        if let path = store.selectedPath, FileViewerFeature.isMarkdown(path) {
          Text("Preview").tag(FileViewerFeature.State.Mode.preview)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(maxWidth: 220)
      .disabled(store.selectedPath == nil)
```

(b) In the `content` `@ViewBuilder`'s `.loaded` branch, dispatch on `store.mode` (not just which optional is set) so preview vs source is unambiguous:
```swift
    case .loaded(let loaded):
      switch store.mode {
      case .diff:
        if let diff = loaded.fileDiff {
          DiffView(fileDiff: diff)
        } else {
          ContentUnavailableView("Nothing to show", systemImage: "doc")
        }
      case .source:
        SourceView(text: loaded.rawText ?? "")
      case .preview:
        MarkdownPreviewView(text: loaded.rawText ?? "")
      }
```

- [ ] **Step 3: Build the app to confirm `import MarkdownUI` links + views compile.**
```bash
SUPACODE_SKIP_PREFLIGHT=1 DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer make build-app
```
Expected: build succeeds (this is the real verification that MarkdownUI is linked from Task 1).

- [ ] **Step 4: Lint.**
```bash
mise exec -- swiftlint lint --quiet supacode/Features/FileViewer/Views/MarkdownPreviewView.swift supacode/Features/FileViewer/Views/FileViewerView.swift
mise exec -- swift-format lint --configuration .swift-format.json supacode/Features/FileViewer/Views/MarkdownPreviewView.swift supacode/Features/FileViewer/Views/FileViewerView.swift
```

- [ ] **Step 5: Commit.**
```bash
git add supacode/Features/FileViewer/Views/MarkdownPreviewView.swift supacode/Features/FileViewer/Views/FileViewerView.swift
git commit -m "Add MarkdownPreviewView and wire preview mode into FileViewerView"
```

---

## Manual verification (after Task 3)
- Select a changed `.md` file → the Preview segment appears; toggle Preview → rendered markdown; Source → raw monospaced; Diff → unified diff.
- Select a `.swift` file → no Preview segment; Diff/Source only. If you were in Preview on a markdown file then tap a `.swift`, mode falls back to Source.
- Verify markdown renders legibly in light and dark.

---

## Self-Review (completed during planning)
- **Spec coverage (design §5):** MarkdownUI added via Tuist (both manifests) ✅ (Task 1); `MarkdownPreviewView` rendering ✅ (Task 3); `.preview` mode + reuse of the source text-load path ✅ (Task 2); Preview surfaced only for markdown ✅ (Task 3); theming = system-color/`colorScheme`-adaptive default ✅. Mode-by-extension AUTO-defaulting is explicitly deferred to Phase 4 (scope note) with the `isMarkdown` seam provided now. Code-block syntax highlighting inside markdown stays deferred (Phase-1 decision).
- **Type consistency:** `Mode.preview`, `isMarkdown(_:)`, and the `content` switch over `store.mode` are consistent across reducer, tests, and view. `MarkdownPreviewView(text:)` matches `SourceView(text:)`'s shape.
- **Placeholder scan:** no TBD. Two API-uncertainty points are flagged with concrete fallbacks: the MarkdownUI version pin (`2.4.1`, bump if it won't resolve) and the `Markdown(_:)` initializer form (adjust to resolved API). Both are real external-package unknowns, not placeholders — the implementer resolves them against the actual resolved package and reports what was used.
- **Folded Phase-2 Minors:** `fileTapped` mode-preserve + same-file guard, `.id`-based auto-select, `contentFailed` test — all included in Task 2 (the file Phase 3 already edits). Remaining Phase-2 Minors (DiffView gutter width/textSelection, ChangedFilesParser `firstRange`) are unrelated to Phase 3 files and stay deferred to a final cleanup.

---

## Next phase (separate plan)
- **Phase 4:** ghostty `RepeatableLink.parseCLI` patch + `link` config + bridge resolve/validate/route (incl. **path-containment validation** under `worktreeURL` per the Phase 2 review) + `onOpenWorktreeFile` → a FileViewer external-open action that opens the pane and uses `defaultMode(forPath:)` (built on `isMarkdown`) so `.md` opens in preview.
