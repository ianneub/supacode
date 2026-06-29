# Design: In-app File Viewer (Preview + Source + Diff) and Clickable Terminal File Paths

**Date:** 2026-06-29
**Branch:** `file-viewer`
**Status:** approved design — verified against the codebase and a feasibility spike; supersedes the original Downloads spec where they differ.

This document is the consolidated, decision-locked version of the original
`2026-06-29-fileviewer-and-terminal-file-links-spec.md`. It folds in (a) corrections from
reading the actual code, (b) the result of a feasibility spike on the terminal-link feature, and
(c) four product decisions taken during brainstorming. Sections marked **[verified]** were
confirmed against source with file:line evidence; **[corrected]** flags where this design departs
from the original spec.

---

## 1. Goals

One surface, two entry points, three modes:

1. **Diff viewer** — file list + per-file inline unified diff for a worktree.
2. **Markdown preview** — render `.md` nicely themed.
3. **Click-to-open from the terminal** — cmd-click a file path printed by an agent and open it in the viewer.

**Key decision:** build **one `Features/FileViewer`** rendering a worktree file in mode
`preview` | `source` | `diff`, reached from two entry points (the diff file list, and terminal
cmd-click). Do **not** build three separate viewers.

### Decisions taken during brainstorming
- **Sequencing:** spike the risky cmd-click feature first (done — see §7), then build the
  low-risk viewer, then wire cmd-click last.
- **Mount UX:** **collapsible side pane** beside the terminal (not a full-area swap, not a separate window).
- **Markdown:** use the **MarkdownUI** dependency.
- **Syntax highlighting:** **deferred** — `SourceView` is plain monospaced for this pass; diff
  coloring still comes from the theme. No syntax-highlighter dependency is added now.
- **Default `DiffScope`:** `.workingTreeVsBase` (everything the worktree changed vs its base ref).

### Non-goals (out of scope this pass)
- Interactive staging / unstaging / partial-hunk staging.
- Editing files (read-only).
- Side-by-side (split) diff — start with **inline unified**.
- Committing/pushing/any write git ops.
- Syntax highlighting (deferred).
- Live-reload of preview on disk change (follow-up; `WorktreeInfoWatcher` could feed this later).
- Separate-window viewer.

---

## 2. Architecture

```
Terminal (libghostty)                 Diff file list
   │ cmd-click path                       │ select file
   └───────────────┐             ┌────────┘
                   ▼             ▼
            Features/FileViewer (TCA)
            state.mode ∈ { preview, source, diff }
                   │
        ┌──────────┼───────────┐
        ▼          ▼           ▼
   MarkdownUI   plain text   DiffView(+UnifiedDiffParser)
                   │
            Clients/Git (new diff funcs on GitClient + GitClientDependency)
```

**Mount:** a **collapsible side pane** via the existing `SplitView` at the `detailContent` level
inside `supacode/Features/Repositories/Views/WorktreeDetailView.swift`, as a sibling of
`WorktreeTerminalTabsView`. The terminal's own split-tree is Ghostty-surface-specific, so a
(non-surface) FileViewer cannot live inside it — it mounts one level up. **[corrected]** The
original spec called this a generic "tab/pane alongside the terminal"; the concrete constraint is
the surface split-tree.

**Store ownership:** `WorktreeDetailView` is owned by the **root `AppFeature` store**
(`@Bindable var store: StoreOf<AppFeature>`), not a dedicated worktree-detail reducer. **[corrected]**
The `FileViewerFeature` child store is scoped from **`RepositoriesFeature`** (where worktree
selection and the worktree model live), with the terminal cmd-click callback delegated up through
`AppFeature` to reach it. Final scoping mechanics are pinned in the implementation plan.

---

## 3. Phase 1 — GitClient diff data layer (no UI)

**Files:** `supacode/Clients/Git/GitClient.swift`, `supacode/Clients/Repositories/GitClientDependency.swift`.

**[verified]** The `GitClient` is a `struct` whose methods are `nonisolated func ... async throws`,
using `runGit(operation:arguments:)` → `shell.run` (non-login) with git's `-C <path>` flag. It
already has `lineChanges` (`git diff HEAD --shortstat`), `parseShortstat`, and base-ref helpers
`automaticWorktreeBaseRef(for:)` / `preferredBaseRef(remote:localHead:)` (the latter delegate to
`SupacodeSettingsShared/Clients/Settings/GitReferenceQueries.swift`). **Reuse all of this.**

**[corrected]** The TCA dependency is a **separate struct-of-closures, `GitClientDependency`**
(`@Dependency(\.gitClient)`), registered via `DependencyKey` with `liveValue = make(shell: .live)`.
New diff functions must be added in **two** places:
1. Implementation on the `GitClient` struct.
2. Closures on `GitClientDependency` + wired in `make(shell:)` + a `testValue` stub.

### Models (new — `Features/FileViewer/Models/` or `Domain/`)
```swift
enum DiffFileStatus: Equatable { case added, modified, deleted, renamed, copied, untracked }

struct DiffFileSummary: Equatable, Identifiable {
  var id: String { newPath ?? oldPath ?? "" }
  let status: DiffFileStatus
  let oldPath: String?      // for renames/copies
  let newPath: String?
  let added: Int
  let removed: Int
  let isBinary: Bool
}

enum DiffScope: Equatable {
  case workingTreeVsHead    // uncommitted changes only
  case workingTreeVsBase    // everything the worktree changed vs its base ref  ← DEFAULT
  case staged
}

struct DiffLine: Equatable {
  enum Kind { case context, addition, deletion, noNewlineMarker }
  let kind: Kind
  let oldNumber: Int?
  let newNumber: Int?
  let text: String
}

struct DiffHunk: Equatable {
  let header: String        // the @@ ... @@ line
  let oldStart: Int; let oldCount: Int
  let newStart: Int; let newCount: Int
  let lines: [DiffLine]
}

struct FileDiff: Equatable {
  let path: String
  let isBinary: Bool
  let hunks: [DiffHunk]
}
```

### New functions
```swift
// On GitClient (struct):
nonisolated func changedFiles(at worktreeURL: URL, scope: DiffScope) async throws -> [DiffFileSummary]
nonisolated func fileDiff(at worktreeURL: URL, path: String, scope: DiffScope) async throws -> FileDiff

// On GitClientDependency (closures), wired through make(shell:) + testValue:
var changedFiles: @Sendable (URL, DiffScope) async throws -> [DiffFileSummary]
var fileDiff: @Sendable (URL, String, DiffScope) async throws -> FileDiff
```

### Underlying git commands (all via `runGit` + `-C <path>`)
- **File list:** `diff --name-status --find-renames <base>` merged with `diff --numstat <base>`
  for +/- counts. Untracked: `ls-files --others --exclude-standard`, marked `.untracked`.
- **Per-file patch:** `diff <base> -- <file>` (add `--cached` for `.staged`). Untracked file →
  render whole file as additions (`diff --no-index /dev/null <file>`, or synthesize an all-addition hunk).
- **`<base>`:** `.workingTreeVsBase` → `automaticWorktreeBaseRef`; `.workingTreeVsHead` → `HEAD`.

### `UnifiedDiffParser` (new, pure, `BusinessLogic/`, well-tested)
Turns raw `git diff` output into `[DiffHunk]`. Handles: `@@ -a,b +c,d @@` headers (counts that
omit `,1`), context/addition/deletion prefixes, `\ No newline at end of file`, renames
(`rename from`/`rename to`), and binary files (`Binary files ... differ` → `isBinary = true`, no
hunks). The fiddliest part — covered by unit tests in `supacodeTests/`.

---

## 4. Phase 2 — FileViewer feature + Source/Diff views + mount

**New:** `supacode/Features/FileViewer/{Reducer,Views,Models,BusinessLogic}` **[verified]** matching
the `Features/Repositories` layout. `Features/` is a globbed Tuist buildable folder, so new files
need no manual project edits.

### State
```swift
@ObservableState
struct FileViewerState: Equatable {
  var worktreeURL: URL
  var filePath: String              // worktree-relative
  var mode: Mode
  enum Mode: Equatable { case preview, source, diff }

  var diffScope: DiffScope = .workingTreeVsBase
  var content: LoadState<Loaded> = .idle
  enum LoadState<T: Equatable>: Equatable { case idle, loading, loaded(T), failed(String) }

  struct Loaded: Equatable {
    var rawText: String?            // for preview/source
    var fileDiff: FileDiff?         // for diff
  }
}
```

### Reducer
- On appear / `filePath` change / `mode` change: kick a cancellable effect loading the right data —
  `@Dependency(\.gitClient)` for diff, a file-read dependency for preview/source. Reuse the app's
  existing cancellation patterns.
- **Default mode by extension:** `.md`/`.markdown` → `preview`; else → `source`; the diff entry
  point forces `mode = .diff`.
- Mode toggle (segmented control: Preview / Source / Diff), Preview shown only for markdown.

### Views
- `FileViewerView` — top-level, switches on `mode`.
- `MarkdownPreviewView` — Phase 3 (MarkdownUI).
- **`SourceView` — plain monospaced, read-only** (no highlighter this pass). **[corrected]**
- `DiffView` — renders `[DiffHunk]` inline: old/new line-number gutters, addition/deletion/context
  colors from the theme, monospaced, in a `LazyVStack` so large diffs don't render all at once.
- `DiffFileListView` — changed files from `changedFiles`, status icon + `+x/-y` counts; selecting a
  row drives the viewer in `diff` mode. Reuse existing git status assets under `Assets.xcassets`.

### Mount
Collapsible side pane via the existing `SplitView` at the `detailContent` level in
`WorktreeDetailView`, sibling to `WorktreeTerminalTabsView`. The pane slides in on diff-open or
cmd-click and collapses when closed. Keyboard-first behavior consistent with the rest of the app.

---

## 5. Phase 3 — Markdown rendering

- **Dependency:** add **MarkdownUI** (`gonzalezreal/swift-markdown-ui`, MIT). **[corrected]** Wire it
  through Tuist in **both** `Tuist/Package.swift` (the `.package(url:...)` pin) **and** `Project.swift`
  (`.external(name: "MarkdownUI")` on the `supacode` app target), then regenerate. The original spec
  named only `Project.swift`; the URL/version pin lives in `Tuist/Package.swift`.
- **Theming:** map MarkdownUI's theme to the app's light/dark tokens under
  `supacode/Resources/Themes/` so preview matches the terminal's look.
- **Code blocks:** rendered with MarkdownUI's own block styling. No external syntax highlighter this
  pass (deferred decision).

---

## 6. Deferred — syntax highlighting

Not in this pass. `SourceView` and markdown code blocks render as plain monospaced text. Revisit
later (Highlightr for breadth, or tree-sitter for accuracy) once the viewer proves out. Recorded
here so a future pass knows it was a deliberate omission, not an oversight.

---

## 7. Phase 4 — Clickable file paths in the terminal (spiked / de-risked)

### Spike verdict **[verified]**
A **ghostty source patch is required**, but everything downstream of it already works.

- Ghostty's `link` config option exists (`src/config/Config.zig`, `RepeatableLink`) and its doc says
  it's meant to match "URLs, file paths, etc." — **but at the pinned commit its parser is a stub**:
  `RepeatableLink.parseCLI` returns `error.NotImplemented` (`Config.zig:~8545`), and the field's doc
  literally reads *"TODO: This can't currently be set!"* So no config text can register a custom path
  regex today.
- A custom link's only action is `.open`, which flows: `processLinks` (`Surface.zig:~4334`) →
  `openUrl` (`Surface.zig:~5949`) → `performAction(.open_url)` → `GHOSTTY_ACTION_OPEN_URL`
  (`include/ghostty.h`). This is the existing interception point at `GhosttySurfaceBridge.swift:461`
  (`NSWorkspace.shared.open(request.url)`).
- **Bonus:** ghostty already resolves bare relative paths against the terminal pwd **and
  existence-checks them** (`resolvePathForOpening`, `Surface.zig:~2045`). So a chunk of the original
  spec's "resolve and validate" is already handled. It does **not** strip a `:line:col` suffix — that
  token fails the existence check and ghostty falls back to the raw string, so `path:line` handling is
  ours to own (regex capture + app-side stripping).
- There is **no** `ghostty_config_load_string` C API; config text is injected via a temp `.conf`
  file. The app **already does this** in `GhosttyRuntime.loadBundledOverrides` →
  `ghostty_config_load_file`, building config text in `bundledOverridesString`. `link` is an
  **app-level** option (lives on `ghostty_config_t`, not the per-surface `ghostty_surface_config_s`),
  so it belongs in that override string.

### Changes

**1. ghostty patch (`patches/`).** Implement `RepeatableLink.parseCLI` **minimally** — parse
`link = <regex>` into an `inputpkg.Link` with a fixed `.open` action and a cmd-hover highlight.
Rationale: keeping the parser tiny means the **path regex lives in Swift config text**
(`bundledOverridesString`), so tuning it against real agent output is a fast app rebuild, not a slow
ghostty rebuild. The patch fits the `patches/*.patch` mechanism (it patches `Config.zig` in the
submodule working tree) and is a candidate for upstreaming (it closes upstream's own TODO).

**2. Add the link regex to config.** Add a `link = <path-regex>,...` line to `bundledOverridesString`
in `GhosttyRuntime`. The regex matches relative/absolute path-like tokens with an optional
`:line[:col]` suffix (e.g. `docs/foo/bar.md`, `./app/models/user.rb:42`, `/abs/path/file.swift`).
Start anchored — require a path separator or a known file extension — to limit false positives;
tune against real output. Must not clobber the built-in URL link (`link-url`).

**3. Resolve / validate / route in the bridge.** In the `GHOSTTY_ACTION_OPEN_URL` case
(`GhosttySurfaceBridge.swift:454-463`), branch **before** the `NSWorkspace.open` call:
- Strip any `:line:col` suffix and carry it along.
- If the URL is a local file (no scheme / `file://`): ghostty has already resolved relative paths
  against pwd and existence-checked; the app adds the **worktree-escape guard** (reject paths outside
  the worktree root; fall back to worktree working directory if pwd is unknown).
- If it resolves to an existing in-worktree file → fire a **new bridge callback**
  `onOpenWorktreeFile?(_ url: URL, _ line: Int?)`, wired like the existing `on…` closures
  (`onTitleChange`, etc., `GhosttySurfaceBridge.swift:52-73`). Thread it up `GhosttySurfaceView` →
  the Terminal feature → the reducer owning the FileViewer, which opens the viewer with the resolved
  path, mode chosen by extension (`.md` → `preview`, else `source`), optionally jumping to `line`.
- Otherwise (external URL, file outside the worktree, non-text like image/PDF) → **fall through to
  `NSWorkspace.shared.open`** so current behavior is preserved.

**4. (Polish) Hover affordance.** Use the already-reported `state.mouseOverLink` for cmd-hover
underline/tooltip. Cmd-click is the activation gesture (ghostty itself decides link activation on
cmd-click; the app does not gate mouse delivery on the command modifier).

---

## 8. Edge cases
- Renamed / copied files in the diff list (show `old → new`).
- Binary files (no diff body; label as binary).
- Untracked files (render as all-additions / whole-file source).
- Very large files / diffs — lazy render; consider a soft cap with a "load anyway" affordance.
- Files deleted in the worktree (diff shows deletions; clicking a deleted path from the terminal
  fails gracefully, not a crash).
- Paths with spaces, and `file:line:col` suffixes, in the terminal matcher.
- `state.pwd` not yet known (no OSC 7 / `GHOSTTY_ACTION_PWD` yet) — fall back to worktree working dir.
- Path resolving outside the worktree root — refuse, fall back to `NSWorkspace`.
- Non-text files cmd-clicked (images, PDFs) — fall back to `NSWorkspace.open`.

---

## 9. Testing
Unit tests under `supacodeTests/`:
- `GitClient.changedFiles` parsing: name-status + numstat merge, renames, untracked, binary.
- `UnifiedDiffParser`: hunk headers (with/without explicit counts), additions/deletions/context,
  `\ No newline at end of file`, renames, binary.
- Terminal path resolution: relative vs absolute, `:line:col` stripping, pwd-fallback,
  worktree-escape rejection, non-existent path.
- `FileViewer` reducer: mode-by-extension defaulting, load/loaded/failed transitions, cancellation.

Manual verification:
- Run an agent that writes a file; cmd-click the printed path → opens in preview (`.md`) / source.
- Select a changed file in the diff list → correct unified diff renders.
- Toggle Preview/Source/Diff; verify theming in light and dark.

---

## 10. Build / tooling notes
- `git submodule update --init --recursive` first (ghostty, zmx, git-wt).
- Tooling via **mise**; ensure `~/.local/bin` on `PATH`. Run `make doctor` first on a new machine.
- On **macOS 26.4+** the GhosttyKit build needs **Xcode 26.3** (pinned Zig can't link the 26.4+ SDK);
  the build auto-detects a Zig-linkable Xcode. The ghostty patch in Phase 4 **requires a ghostty
  rebuild** (`make build-ghostty-xcframework`) — budget for it. Run one ghostty build at a time
  (patch apply/revert shares the submodule working tree).
- New SPM package (MarkdownUI): add to **`Tuist/Package.swift`** (URL/version pin) **and**
  **`Project.swift`** (`.external(name:)`), then regenerate.
- Before finishing: `make check` (format + lint), `make test`, `make build-app`. Match
  `.swift-format.json` / `.swiftlint.yml`.

---

## 11. Commit / implementation sequence
1. **GitClient diff layer** — models + `changedFiles` + `fileDiff` (on `GitClient` *and*
   `GitClientDependency`) + `UnifiedDiffParser` + tests. No UI.
2. **FileViewer feature** — reducer/state + plain `SourceView` + `DiffView`; mount as collapsible
   side pane in `WorktreeDetailView` behind the diff file list.
3. **Markdown** — add MarkdownUI (Tuist) + `MarkdownPreviewView`; mode-by-extension + theming.
4. **Terminal cmd-click** — ghostty `parseCLI` patch + `link` config line + bridge
   resolve/validate/route + `onOpenWorktreeFile` callback wiring + tests.
5. **Polish** — hover affordance, large-file caps, keyboard nav.

(Syntax highlighting and live-reload are explicit follow-ups, not in this sequence.)

---

## 12. Settled questions
- **Default `DiffScope`** = `.workingTreeVsBase`. ✅
- **Mount** = collapsible side pane via `SplitView` at `detailContent` level. ✅
- **Markdown** = MarkdownUI. ✅
- **Syntax highlighting** = deferred. ✅
- **Live-reload on disk change** = follow-up (not this pass).
- **FileViewer store ownership** = scoped from `RepositoriesFeature`; exact mechanics pinned in the
  implementation plan.
