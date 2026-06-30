# FileViewer Phase 4 — Clickable Terminal File Paths

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** cmd-click a file path printed in the terminal → open it in the FileViewer side pane (instead of the OS), with `:line` support, worktree-containment safety, and `.md` opening in preview.

**Architecture:** A ghostty `patches/` patch implements the stubbed `RepeatableLink.parseCLI` so a custom `link = <regex>` config registers a path matcher whose `.open` action fires `GHOSTTY_ACTION_OPEN_URL`. `GhosttyRuntime` injects that `link` line. `GhosttySurfaceBridge` intercepts `GHOSTTY_ACTION_OPEN_URL` via a new `onOpenWorktreeFile` callback before the `NSWorkspace` fallback. `WorktreeTerminalState` resolves the raw token through a pure, tested `TerminalFileLink` resolver (strip `:line`, resolve vs pwd/worktree, existence + containment check) and emits a `TerminalClient.Event`; `AppFeature` forwards it to `RepositoriesFeature.openFileInViewer`, which opens the pane on the resolved worktree-relative path with mode-by-extension.

**Tech Stack:** Zig 0.15.2 (ghostty patch) / Swift 6 / TCA / swift-testing / GhosttyKit rebuild required.

## Global Constraints
- Target macOS 26.0+, Swift 6.0, MainActor isolation (`@Dependency(Type.self)`, `nonisolated` Sendable value types, `nonisolated CancelID`). Use `SupaLogger`, no `print()`.
- **Security:** never open a resolved path that escapes the worktree root; fall through to `NSWorkspace` for external URLs / out-of-worktree / non-existent / non-text. This is the load-bearing guard (carried from the Phase 2 review).
- System colors only; `store_state_mutation_in_views`; buttons need `.help`. 2-space/120-col/trailing-commas, swiftlint strict (**actually run lint**). No top-level free functions.
- ghostty patches live in `patches/*.patch` (git-apply `-p1` format against the `ThirdParty/ghostty` working tree); the submodule pointer never moves. The build applies them in `scripts/build-ghostty.sh` and reverts on exit.

## Environment — incantations (this machine)
Commit signing OFF locally (overnight headless; user re-signs later) — commit normally.
```bash
# Rebuild GhosttyKit after a ghostty patch change (REQUIRED for Task 1; slow ~minutes):
SUPACODE_SKIP_PREFLIGHT=1 make build-ghostty-xcframework
# App build / focused tests (26.3 toolchain; run in BACKGROUND + poll a log):
SUPACODE_SKIP_PREFLIGHT=1 DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer make build-app
SUPACODE_SKIP_PREFLIGHT=1 DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer \
  xcodebuild test -workspace supacode.xcworkspace -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/CLASSNAME \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation -parallel-testing-enabled NO
# Lint:
mise exec -- swiftlint lint --quiet <files...>
mise exec -- swift-format lint --configuration .swift-format.json <files...>
```
**Verification ceiling:** the end-to-end cmd-click UX (a click actually opening the pane) is **manual QA** — automated verification covers the patch compiling, the config loading without a ghostty diagnostic, the pure resolver's logic, and the reducer wiring. Note this in reports; do not claim the click works without manual confirmation.

---

## File Structure
| File | Responsibility |
| --- | --- |
| `patches/ghostty-link-parsecli.patch` (create) | Implements `RepeatableLink.parseCLI` in ghostty's Config.zig. |
| `supacode/Infrastructure/Ghostty/GhosttyRuntime.swift` (modify) | Add the `link = <regex>` line to `bundledOverridesString`. |
| `supacode/Infrastructure/Ghostty/GhosttySurfaceBridge.swift` (modify) | `onOpenWorktreeFile` callback + intercept in `GHOSTTY_ACTION_OPEN_URL`. |
| `supacode/Features/Terminal/BusinessLogic/TerminalFileLink.swift` (create) | Pure resolver: raw token + pwd + worktree root → validated worktree-relative path + line, or nil. |
| `supacodeTests/TerminalFileLinkTests.swift` (create) | Resolver unit tests. |
| `supacode/Features/Terminal/Models/WorktreeTerminalState.swift` (modify) | Wire `onOpenWorktreeFile` → resolve → emit event. |
| `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift` (modify) | `emit` the new event (if not automatic via the existing helper). |
| `supacode/Clients/Terminal/TerminalClient.swift` (modify) | `Event.openWorktreeFileRequested(worktreeID:path:line:)`. |
| `supacode/Features/App/Reducer/AppFeature.swift` (modify) | Forward `terminalEvent(.openWorktreeFileRequested)` → `.repositories(.openFileInViewer(...))`. |
| `supacode/Features/FileViewer/Reducer/FileViewerFeature.swift` (modify) | `targetLine`, `openFile(path:line:)` action, `defaultMode(forPath:)`. |
| `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift` (modify) | `openFileInViewer(worktreeID:path:line:)` handler. |
| `supacodeTests/FileViewerFeatureTests.swift` / `RepositoriesFileViewerTests.swift` (modify) | Tests for the open-file path. |

---

## Task 1: ghostty patch — implement `RepeatableLink.parseCLI`

**Files:** Create `patches/ghostty-link-parsecli.patch`. Verify via GhosttyKit rebuild + app build + config-load probe.

- [ ] **Step 1: Author the patch.** Implement `parseCLI` to parse `input` as the regex string and append a `Link` mirroring the built-in URL link (`.open` action, cmd/ctrl hover highlight). Create `patches/ghostty-link-parsecli.patch` as a `git apply -p1` diff against `src/config/Config.zig`, replacing the stub body:
```
diff --git a/src/config/Config.zig b/src/config/Config.zig
--- a/src/config/Config.zig
+++ b/src/config/Config.zig
@@ -8540,11 +8540,21 @@ pub const RepeatableLink = struct {
     links: std.ArrayListUnmanaged(inputpkg.Link) = .{},
 
     pub fn parseCLI(self: *Self, alloc: Allocator, input_: ?[]const u8) !void {
-        _ = self;
-        _ = alloc;
-        _ = input_;
-        return error.NotImplemented;
+        const value = input_ orelse return error.ValueRequired;
+        // Empty value resets the user-configured links (the built-in URL
+        // matcher at index 0 is re-added by Config.default, not here).
+        if (value.len == 0) {
+            self.links.clearRetainingCapacity();
+            return;
+        }
+        // Minimal supacode form: the entire value is the regex; the action is
+        // always the system opener and the link is clickable on cmd/ctrl-hover.
+        // (supacode intercepts the resulting open-URL action app-side.)
+        const regex = try alloc.dupe(u8, value);
+        try self.links.append(alloc, .{
+            .regex = regex,
+            .action = .{ .open = {} },
+            .highlight = .{ .hover_mods = inputpkg.ctrlOrSuper(.{}) },
+        });
     }
```
> The `@@` line numbers + context must match the pinned commit (6057f8d2). If they drift, regenerate: temporarily edit `ThirdParty/ghostty/src/config/Config.zig`, `git -C ThirdParty/ghostty diff > patches/ghostty-link-parsecli.patch`, then `git -C ThirdParty/ghostty checkout src/config/Config.zig`. Confirm `inputpkg.ctrlOrSuper` and the `inputpkg.Link` literal shape against Config.zig:3852-3857 (the default URL link) — mirror it exactly. Leave `formatEntry` as the no-op (we never serialize config back).

- [ ] **Step 2: Apply-check the patch.**
```bash
git -C ThirdParty/ghostty apply --check patches/ghostty-link-parsecli.patch && echo "APPLIES CLEAN"
```
(Run from repo root; the script uses the same check.) Expected: `APPLIES CLEAN`. If not, fix the context/line numbers per Step 1's note.

- [ ] **Step 3: Rebuild GhosttyKit with the patch.**
```bash
SUPACODE_SKIP_PREFLIGHT=1 make build-ghostty-xcframework
```
Expected: Zig build succeeds (the patch compiles). If Zig errors (type mismatch on the `Link` literal, `ctrlOrSuper` signature, etc.), fix the patch and re-run. This is the gating risk — iterate here until the build is green.

- [ ] **Step 4: Verify the config registers without a diagnostic.** Temporarily add a probe to confirm ghostty accepts a `link` line (it would previously have errored as a diagnostic). Add to `bundledOverridesString` (Task 2 makes this permanent) a trivial `link = test\n`, build the app, and check the app logs at launch for a ghostty config diagnostic about `link`. Simpler automated proxy: after the rebuild, the symbol exists and `git -C ThirdParty/ghostty apply --reverse --check patches/...` confirms applied. Full validation that a `link` line is accepted happens in Task 2 + manual QA. Record what you verified.

- [ ] **Step 5: Commit.**
```bash
git add patches/ghostty-link-parsecli.patch
git commit -m "Patch ghostty to implement RepeatableLink.parseCLI for custom link regexes"
```
> Do NOT commit the rebuilt `.build/ghostty/GhosttyKit.xcframework` (gitignored). The patch is the artifact; the framework is rebuilt on demand.

---

## Task 2: pure terminal-file-link resolver

**Files:** Create `supacode/Features/Terminal/BusinessLogic/TerminalFileLink.swift`; Test `supacodeTests/TerminalFileLinkTests.swift`.

**Interfaces:** Produces
```swift
enum TerminalFileLink {
  struct Resolved: Equatable { let relativePath: String; let line: Int? }
  static func resolve(rawToken: String, pwd: String?, worktreeRoot: URL, fileManager: FileManager = .default) -> Resolved?
}
```

- [ ] **Step 1: Write the failing tests.** Create `supacodeTests/TerminalFileLinkTests.swift` covering: a relative in-worktree path resolves to its worktree-relative form; absolute in-worktree path; `:line` (and `:line:col`) suffix stripped and `line` captured; resolution against `pwd` when relative; pwd-fallback to worktreeRoot when pwd nil; **rejection of a path escaping the worktree (`../outside`, or absolute outside)**; rejection of a non-existent path; a token with a trailing `:42` where `foo.swift:42` isn't a real file but `foo.swift` is. Use a real temp worktree dir with seeded files (mirror `GitClientDiffTests`' temp-dir pattern). Each assertion concrete.
```swift
import Foundation
import Testing
@testable import supacode

@MainActor
struct TerminalFileLinkTests {
  private func makeWorktree() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root.appending(path: "src"), withIntermediateDirectories: true)
    try "x".write(to: root.appending(path: "src/a.swift"), atomically: true, encoding: .utf8)
    try "y".write(to: root.appending(path: "README.md"), atomically: true, encoding: .utf8)
    return root.standardizedFileURL
  }

  @Test func resolvesRelativePathAgainstPwd() throws {
    let root = try makeWorktree(); defer { try? FileManager.default.removeItem(at: root) }
    let r = TerminalFileLink.resolve(rawToken: "src/a.swift", pwd: root.path, worktreeRoot: root)
    #expect(r == TerminalFileLink.Resolved(relativePath: "src/a.swift", line: nil))
  }

  @Test func stripsLineAndColumnSuffix() throws {
    let root = try makeWorktree(); defer { try? FileManager.default.removeItem(at: root) }
    let r = TerminalFileLink.resolve(rawToken: "src/a.swift:42:7", pwd: root.path, worktreeRoot: root)
    #expect(r == TerminalFileLink.Resolved(relativePath: "src/a.swift", line: 42))
  }

  @Test func rejectsPathEscapingWorktree() throws {
    let root = try makeWorktree(); defer { try? FileManager.default.removeItem(at: root) }
    #expect(TerminalFileLink.resolve(rawToken: "../etc/passwd", pwd: root.path, worktreeRoot: root) == nil)
  }

  @Test func rejectsNonexistentPath() throws {
    let root = try makeWorktree(); defer { try? FileManager.default.removeItem(at: root) }
    #expect(TerminalFileLink.resolve(rawToken: "src/missing.swift", pwd: root.path, worktreeRoot: root) == nil)
  }

  @Test func pwdNilFallsBackToWorktreeRoot() throws {
    let root = try makeWorktree(); defer { try? FileManager.default.removeItem(at: root) }
    let r = TerminalFileLink.resolve(rawToken: "README.md", pwd: nil, worktreeRoot: root)
    #expect(r == TerminalFileLink.Resolved(relativePath: "README.md", line: nil))
  }
}
```

- [ ] **Step 2: Run → RED** (compile failure). - [ ] **Step 3: Implement `TerminalFileLink`.**
```swift
import Foundation

/// Resolves a terminal-matched path token to a validated, worktree-relative
/// file path (+ optional line). Returns nil for tokens that don't resolve to
/// an existing file inside the worktree — the caller falls back to NSWorkspace.
nonisolated enum TerminalFileLink {
  struct Resolved: Equatable, Sendable {
    let relativePath: String
    let line: Int?
  }

  static func resolve(
    rawToken: String,
    pwd: String?,
    worktreeRoot: URL,
    fileManager: FileManager = .default
  ) -> Resolved? {
    let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else { return nil }
    let (pathPart, line) = splitLineSuffix(token)
    guard !pathPart.isEmpty else { return nil }

    let base = (pwd?.isEmpty == false) ? URL(filePath: pwd!) : worktreeRoot
    let candidate: URL =
      pathPart.hasPrefix("/")
      ? URL(filePath: pathPart).standardizedFileURL
      : base.appending(path: pathPart).standardizedFileURL

    let root = worktreeRoot.standardizedFileURL
    let rootPath = root.path(percentEncoded: false)
    let candidatePath = candidate.path(percentEncoded: false)
    // Containment: candidate must be the root or strictly under it.
    let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    guard candidatePath == rootPath || candidatePath.hasPrefix(rootPrefix) else { return nil }
    guard fileManager.fileExists(atPath: candidatePath) else { return nil }

    let relative = String(candidatePath.dropFirst(rootPrefix.count))
    guard !relative.isEmpty else { return nil }
    return Resolved(relativePath: relative, line: line)
  }

  /// Splits a trailing `:line` or `:line:col` suffix off a path token.
  private static func splitLineSuffix(_ token: String) -> (path: String, line: Int?) {
    let parts = token.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    guard parts.count >= 2, let last = parts.last else { return (token, nil) }
    // `path:line`
    if parts.count == 2, let line = Int(parts[1]) {
      return (parts[0], line)
    }
    // `path:line:col`
    if parts.count == 3, Int(parts[2]) != nil, let line = Int(parts[1]) {
      return (parts[0], line)
    }
    _ = last
    return (token, nil)  // not a line-suffix shape (e.g. a Windows path) → treat whole token as path
  }
}
```
> Note: this assumes paths without literal `:` other than a line suffix. Windows-style `C:\` won't appear in this macOS app's worktrees. Tune in manual QA if needed.

- [ ] **Step 4: Run → GREEN.** - [ ] **Step 5: Lint.** - [ ] **Step 6: Commit** (`Add TerminalFileLink path resolver with worktree containment`).

---

## Task 3: bridge callback + event wiring + FileViewer open-file entry

This task threads the resolved file from the bridge to the pane. It modifies several files; build + reducer tests verify the Swift side (the click itself is manual QA).

**Files:** GhosttySurfaceBridge.swift, WorktreeTerminalState.swift, WorktreeTerminalManager.swift, TerminalClient.swift, AppFeature.swift, FileViewerFeature.swift, RepositoriesFeature.swift, + tests.

- [ ] **Step 1: Bridge callback.** In `GhosttySurfaceBridge.swift` add (near the other `on…` props ~line 52-73):
```swift
  /// Cmd-clicked file-path token (raw matched text) + the surface's pwd.
  /// Return true if handled (opened in-app); false to fall through to NSWorkspace.
  var onOpenWorktreeFile: ((_ rawToken: String, _ pwd: String?) -> Bool)?
```
In the `GHOSTTY_ACTION_OPEN_URL` case (~line 454-463), BEFORE `NSWorkspace.shared.open(request.url)`:
```swift
      if let rawUrl, onOpenWorktreeFile?(rawUrl, state.pwd) == true {
        return true
      }
```
(Keep the existing `NSWorkspace` line as the fallback when the callback is nil or returns false.)

- [ ] **Step 2: TerminalClient event.** In `TerminalClient.swift` `Event` enum (~line 101) add:
```swift
    case openWorktreeFileRequested(worktreeID: Worktree.ID, path: String, line: Int?)
```

- [ ] **Step 3: Wire the callback in `WorktreeTerminalState`.** In the surface-callback wiring helper (mirror `onChildExited`/`onDesktopNotification` at ~line 1574-1582), capturing the worktree:
```swift
    view.bridge.onOpenWorktreeFile = { [weak self, weak view] rawToken, pwd in
      guard let self, let view, self.isLiveSurface(view) else { return false }
      guard let root = self.worktree.localWorkingDirectory,
        let resolved = TerminalFileLink.resolve(rawToken: rawToken, pwd: pwd, worktreeRoot: root)
      else { return false }
      self.manager?.emitOpenWorktreeFile(worktreeID: self.worktree.id, path: resolved.relativePath, line: resolved.line)
      return true
    }
```
> Match how `self` reaches the manager + `emit` in this file (the `onDesktopNotification` path shows the exact `self.handle…` → manager `emit` route). Add an `emitOpenWorktreeFile(...)` helper on `WorktreeTerminalManager` that sends `.openWorktreeFileRequested(...)` on the event continuation, mirroring the existing notification emit. Confirm `self.worktree` / `manager` accessors exist on `WorktreeTerminalState`; adjust names to the real ones.

- [ ] **Step 4: Forward in `AppFeature`.** Mirror the `setupScriptConsumed` forward (~line 1057-1058):
```swift
      case .terminalEvent(.openWorktreeFileRequested(let worktreeID, let path, let line)):
        return .send(.repositories(.openFileInViewer(worktreeID: worktreeID, path: path, line: line)))
```

- [ ] **Step 5: FileViewerFeature open-file entry + `defaultMode`.** Add to `State`: `var targetLine: Int?`. Add a static helper:
```swift
  static func defaultMode(forPath path: String) -> State.Mode {
    isMarkdown(path) ? .preview : .source
  }
```
Add an action `case openFile(path: String, line: Int?)` and handler: set `selectedPath = path`, `targetLine = line`, `mode = Self.defaultMode(forPath: path)`, then `loadContent`. (The visual scroll-to-`line` in DiffView/SourceView is a follow-up; carrying `targetLine` is the Phase 4 deliverable. Optionally scroll if trivial.)

- [ ] **Step 6: RepositoriesFeature `openFileInViewer`.** Add `case openFileInViewer(worktreeID: Worktree.ID, path: String, line: Int?)` near `.toggleFileViewer`. Handler: resolve the worktree's `localWorkingDirectory`; if `fileViewer` is nil or its `worktreeURL` differs, create `FileViewerFeature.State(worktreeURL:)`; then `.send(.fileViewer(.openFile(path:line:)))` (or set state + return the child effect). Ensure the pane opens. Classify both new actions in `SidebarStructure.cacheInvalidations` as `[]` (no recompute), like `toggleFileViewer`.

- [ ] **Step 7: Tests.** FileViewerFeatureTests: `openFile` sets path/line/mode (markdown→preview, else source) and loads. RepositoriesFileViewerTests: `openFileInViewer` opens the pane for the selected worktree with the right path. Run both classes + RepositoriesFeatureTests regression — all green.

- [ ] **Step 8: Add the `link` regex to config.** In `GhosttyRuntime.bundledOverridesString` add a `link` line. Conservative path regex (anchored to require a separator or known extension; avoid clobbering URLs which the built-in matcher already handles):
```
link = (?:\./|/|\.\./|[\w.\-]+/)[\w./\-]+(?::\d+(?::\d+)?)?
```
> This is a STARTING regex — it WILL need tuning against real agent output during manual QA (the plan can't perfect it blind). Keep it in Swift config so tuning is an app rebuild, not a ghostty rebuild. Document it as provisional.

- [ ] **Step 9: Build + lint + commit.** Build the app, run the test classes, lint all touched files. Commit (`Route terminal cmd-click of in-worktree paths into the FileViewer`).

---

## Manual QA (morning — the click cannot be auto-verified)
- Run an agent that prints a relative path (e.g. `docs/foo.md`); cmd-hover → underline; cmd-click → pane opens that file (markdown → preview). Click a `.swift` path → source. Click `path:42` → opens (line carried).
- Click an external URL (`https://…`) → still opens in browser (fallback intact). Click a path outside the worktree → opens in Finder/NSWorkspace (not the pane). Click a non-existent path → NSWorkspace (graceful, no crash).
- Tune the `link` regex in `bundledOverridesString` against real agent output (false positives/negatives) — app rebuild only.

## Self-Review (planning)
- Spec §7 coverage: parseCLI patch ✅(T1); `link` config injection ✅(T3 S8); bridge intercept + `onOpenWorktreeFile` ✅(T3 S1); resolve/validate incl. **worktree-escape rejection + `:line` strip + pwd fallback** ✅(T2, tested); route into FileViewer ✅(T3); external/out-of-worktree/non-existent → NSWorkspace fallback ✅(T3 S1 + T2 nil). Hover affordance is ghostty-native once the link registers. mode-by-extension via `defaultMode` ✅(T3 S5).
- Risk register: T1 (Zig patch compile) is the gate; T3 wiring spans many files (names verified by research but confirm at edit time); the regex is provisional (manual tuning); scroll-to-line visual is deferred (line is carried, not yet scrolled-to).
- Placeholder scan: the patch `@@` line numbers and several Swift insertion points are anchored to researched line numbers — the implementer confirms/adjusts against the real files (named in each step), not guesses. No TBD.
