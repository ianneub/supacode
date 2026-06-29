# FileViewer Phase 1 — GitClient Diff Data Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a read-only, structured git-diff data layer to `GitClient` (changed-file list + per-file unified diff) with two pure, well-tested parsers, exposed through the `GitClientDependency` TCA client. No UI.

**Architecture:** Two pure parsers (`UnifiedDiffParser`, `ChangedFilesParser`) convert raw `git` text into value types defined in `DiffModels.swift`. `GitClient` gains two thin shell-out methods (`changedFiles`, `fileDiff`) that build git argument vectors via the existing `runGit` runner and delegate parsing to those parsers. The methods are surfaced as `@Sendable` closures on `GitClientDependency` so reducers consume them via `@Dependency(\.gitClient)`. This is the foundation for Phase 2 (the FileViewer UI), which is a separate plan.

**Tech Stack:** Swift 6, swift-testing (`import Testing`), The Composable Architecture / swift-dependencies, Tuist-generated workspace, prebuilt `Frameworks/GhosttyKit.xcframework` (no Zig rebuild needed for this phase).

## Global Constraints

- Target macOS 26.0+, Swift 6.0.
- New diff functions MUST be added in **two** places: the implementation on the `GitClient` struct AND a `@Sendable` closure on `GitClientDependency` (wired in `make(shell:)`).
- All `GitClient` methods are `nonisolated func ... async throws` (or `async ->` for the non-throwing ones); shell-out goes through the existing `private func runGit(operation:arguments:)` using git's `-C <path>` flag. Do not add a login-shell path.
- All new value types returned through `@Sendable` closures MUST be `Sendable` (and `Equatable`).
- Use `SupaLogger` for any logging — never `print()` or `os.Logger` directly. (Phase 1 needs no logging.)
- Prefer Swift-native APIs (`split`, `firstMatch(of:)`, `replacing`) over Foundation equivalents.
- No top-level free functions — parsers are caseless `enum`s with `static` methods.
- 2-space indentation, 120-char lines, trailing commas mandatory. Run `make check` before finishing.
- Default `DiffScope` is `.workingTreeVsBase` (resolved via the existing `automaticWorktreeBaseRef`).

---

## One-time setup (before Task 1)

- [ ] **Step 0: Confirm the toolchain builds and the workspace generates.**

Run:
```bash
make build-app
```
Expected: a successful Debug build. This generates the Tuist workspace (`supacode.xcworkspace`) and links the prebuilt GhosttyKit, so subsequent `-only-testing` runs are fast. If this fails, run `make doctor` and resolve prerequisites before proceeding.

**Test-run command used throughout this plan** (single class, fast):
```bash
xcodebuild test -workspace supacode.xcworkspace -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/CLASSNAME \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation -parallel-testing-enabled NO
```
If the workspace name ever differs or generation is stale, `make test` (runs everything, always regenerates) is the reliable fallback.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `supacode/Clients/Git/DiffModels.swift` (create) | The six diff value types: `DiffFileStatus`, `DiffFileSummary`, `DiffScope`, `DiffLine`, `DiffHunk`, `FileDiff`. |
| `supacode/Clients/Git/UnifiedDiffParser.swift` (create) | Pure: raw single-file `git diff` text → `FileDiff` (hunks, binary detection). |
| `supacode/Clients/Git/ChangedFilesParser.swift` (create) | Pure: merge `--name-status` + `--numstat` + untracked list → `[DiffFileSummary]`. |
| `supacode/Clients/Git/GitClient.swift` (modify) | Add `GitOperation` cases; `changedFiles(at:scope:)`, `fileDiff(at:path:scope:)`, private `diffBaseArguments`, private `syntheticAdditionDiff`. |
| `supacode/Clients/Repositories/GitClientDependency.swift` (modify) | Add `changedFiles` / `fileDiff` closures + wire them in `make(shell:)`. |
| `supacodeTests/UnifiedDiffParserTests.swift` (create) | Unit tests for `UnifiedDiffParser`. |
| `supacodeTests/ChangedFilesParserTests.swift` (create) | Unit tests for `ChangedFilesParser`. |
| `supacodeTests/GitClientDiffTests.swift` (create) | Mock-shell tests for `changedFiles` / `fileDiff` (argument shape + delegation + untracked synthesis). |

---

## Task 1: Diff models + UnifiedDiffParser

**Files:**
- Create: `supacode/Clients/Git/DiffModels.swift`
- Create: `supacode/Clients/Git/UnifiedDiffParser.swift`
- Test: `supacodeTests/UnifiedDiffParserTests.swift`

**Interfaces:**
- Consumes: nothing (foundation task).
- Produces:
  - `DiffFileStatus`, `DiffFileSummary`, `DiffScope`, `DiffLine` (+ `DiffLine.Kind`), `DiffHunk`, `FileDiff` — all `Equatable, Sendable`.
  - `enum UnifiedDiffParser { static func parse(_ raw: String, path: String) -> FileDiff }`

- [ ] **Step 1: Create the models file.**

Create `supacode/Clients/Git/DiffModels.swift`:
```swift
import Foundation

enum DiffFileStatus: Equatable, Sendable {
  case added, modified, deleted, renamed, copied, untracked
}

struct DiffFileSummary: Equatable, Sendable, Identifiable {
  var id: String { newPath ?? oldPath ?? "" }
  let status: DiffFileStatus
  let oldPath: String?  // for renames/copies and deletions
  let newPath: String?  // nil for deletions
  let added: Int
  let removed: Int
  let isBinary: Bool
}

enum DiffScope: Equatable, Sendable {
  case workingTreeVsHead  // uncommitted changes vs HEAD
  case workingTreeVsBase  // everything the worktree changed vs its base ref (DEFAULT)
  case staged             // staged changes (--cached)
}

struct DiffLine: Equatable, Sendable {
  enum Kind: Equatable, Sendable { case context, addition, deletion, noNewlineMarker }
  let kind: Kind
  let oldNumber: Int?
  let newNumber: Int?
  let text: String
}

struct DiffHunk: Equatable, Sendable {
  let header: String  // the literal "@@ ... @@" line
  let oldStart: Int
  let oldCount: Int
  let newStart: Int
  let newCount: Int
  let lines: [DiffLine]
}

struct FileDiff: Equatable, Sendable {
  let path: String
  let isBinary: Bool
  let hunks: [DiffHunk]
}
```

- [ ] **Step 2: Write the failing tests.**

Create `supacodeTests/UnifiedDiffParserTests.swift`:
```swift
import Foundation
import Testing

@testable import supacode

struct UnifiedDiffParserTests {
  @Test func parsesSingleHunkWithAdditionsDeletionsAndContext() {
    let raw = """
      diff --git a/foo.txt b/foo.txt
      index e69de29..4b825dc 100644
      --- a/foo.txt
      +++ b/foo.txt
      @@ -1,3 +1,4 @@
       context line
      -removed line
      +added line one
      +added line two
       trailing context
      """
    let diff = UnifiedDiffParser.parse(raw, path: "foo.txt")

    #expect(diff.path == "foo.txt")
    #expect(diff.isBinary == false)
    #expect(diff.hunks.count == 1)

    let hunk = diff.hunks[0]
    #expect(hunk.oldStart == 1)
    #expect(hunk.oldCount == 3)
    #expect(hunk.newStart == 1)
    #expect(hunk.newCount == 4)
    #expect(hunk.lines.map(\.kind) == [.context, .deletion, .addition, .addition, .context])

    // Line numbering: context starts both at 1; deletion advances old only; additions advance new only.
    #expect(hunk.lines[0].oldNumber == 1)
    #expect(hunk.lines[0].newNumber == 1)
    #expect(hunk.lines[1].kind == .deletion)
    #expect(hunk.lines[1].oldNumber == 2)
    #expect(hunk.lines[1].newNumber == nil)
    #expect(hunk.lines[2].kind == .addition)
    #expect(hunk.lines[2].oldNumber == nil)
    #expect(hunk.lines[2].newNumber == 2)
    #expect(hunk.lines[4].oldNumber == 3)
    #expect(hunk.lines[4].newNumber == 4)
    #expect(hunk.lines[2].text == "added line one")
  }

  @Test func parsesHunkHeaderWithOmittedCounts() {
    // "@@ -1 +1 @@" — counts omitted, both default to 1.
    let raw = """
      @@ -1 +1 @@
      -old
      +new
      """
    let diff = UnifiedDiffParser.parse(raw, path: "a")
    let hunk = diff.hunks[0]
    #expect(hunk.oldStart == 1)
    #expect(hunk.oldCount == 1)
    #expect(hunk.newStart == 1)
    #expect(hunk.newCount == 1)
  }

  @Test func parsesMultipleHunks() {
    let raw = """
      @@ -1,1 +1,1 @@
      -a
      +b
      @@ -10,1 +10,1 @@
      -c
      +d
      """
    let diff = UnifiedDiffParser.parse(raw, path: "a")
    #expect(diff.hunks.count == 2)
    #expect(diff.hunks[1].oldStart == 10)
    #expect(diff.hunks[1].lines.map(\.kind) == [.deletion, .addition])
  }

  @Test func capturesNoNewlineMarker() {
    let raw = """
      @@ -1,1 +1,1 @@
      -old
      +new
      \\ No newline at end of file
      """
    let diff = UnifiedDiffParser.parse(raw, path: "a")
    let kinds = diff.hunks[0].lines.map(\.kind)
    #expect(kinds == [.deletion, .addition, .noNewlineMarker])
    #expect(diff.hunks[0].lines.last?.text == "No newline at end of file")
    #expect(diff.hunks[0].lines.last?.oldNumber == nil)
    #expect(diff.hunks[0].lines.last?.newNumber == nil)
  }

  @Test func detectsBinaryFile() {
    let raw = """
      diff --git a/img.png b/img.png
      Binary files a/img.png and b/img.png differ
      """
    let diff = UnifiedDiffParser.parse(raw, path: "img.png")
    #expect(diff.isBinary == true)
    #expect(diff.hunks.isEmpty)
  }

  @Test func ignoresPreHunkHeaderLinesAndTrailingNewline() {
    // Leading diff --git/index/---/+++ lines are skipped; a trailing blank
    // line from the final newline must not become a spurious context line.
    let raw = "diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1,1 +1,1 @@\n context\n"
    let diff = UnifiedDiffParser.parse(raw, path: "x")
    #expect(diff.hunks.count == 1)
    #expect(diff.hunks[0].lines.count == 1)
    #expect(diff.hunks[0].lines[0].kind == .context)
    #expect(diff.hunks[0].lines[0].text == "context")
  }

  @Test func preservesEmptyContextLine() {
    // A blank line inside a hunk arrives as a single-space prefix " ".
    let raw = "@@ -1,2 +1,2 @@\n first\n \n"
    let diff = UnifiedDiffParser.parse(raw, path: "x")
    #expect(diff.hunks[0].lines.count == 2)
    #expect(diff.hunks[0].lines[1].kind == .context)
    #expect(diff.hunks[0].lines[1].text == "")
  }
}
```

- [ ] **Step 3: Run the tests to verify they fail.**

Run:
```bash
xcodebuild test -workspace supacode.xcworkspace -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/UnifiedDiffParserTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation -parallel-testing-enabled NO
```
Expected: build/compile failure — `UnifiedDiffParser` is not defined yet.

- [ ] **Step 4: Implement `UnifiedDiffParser`.**

Create `supacode/Clients/Git/UnifiedDiffParser.swift`:
```swift
import Foundation

/// Parses raw `git diff` output for a *single file* into a structured `FileDiff`.
/// Pure and synchronous so it is unit-testable without shelling out.
enum UnifiedDiffParser {
  static func parse(_ raw: String, path: String) -> FileDiff {
    let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    if lines.contains(where: { $0.hasPrefix("Binary files") || $0.hasPrefix("GIT binary patch") }) {
      return FileDiff(path: path, isBinary: true, hunks: [])
    }

    var hunks: [DiffHunk] = []
    var pending: (header: String, oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)?
    var pendingLines: [DiffLine] = []
    var oldNumber = 0
    var newNumber = 0

    func flush() {
      guard let pending else { return }
      hunks.append(
        DiffHunk(
          header: pending.header,
          oldStart: pending.oldStart,
          oldCount: pending.oldCount,
          newStart: pending.newStart,
          newCount: pending.newCount,
          lines: pendingLines
        )
      )
      pendingLines = []
    }

    for line in lines {
      if line.hasPrefix("@@") {
        flush()
        if let header = parseHunkHeader(line) {
          pending = (line, header.oldStart, header.oldCount, header.newStart, header.newCount)
          oldNumber = header.oldStart
          newNumber = header.newStart
        } else {
          pending = nil
        }
        continue
      }

      // Skip anything before the first hunk header (diff --git, index, ---, +++)
      // and the trailing empty string produced by a final newline.
      guard pending != nil, !line.isEmpty else { continue }

      if line.hasPrefix("\\") {
        // "\ No newline at end of file" — drop the leading "\ ".
        pendingLines.append(
          DiffLine(kind: .noNewlineMarker, oldNumber: nil, newNumber: nil, text: String(line.dropFirst(2)))
        )
      } else if line.hasPrefix("+") {
        pendingLines.append(
          DiffLine(kind: .addition, oldNumber: nil, newNumber: newNumber, text: String(line.dropFirst()))
        )
        newNumber += 1
      } else if line.hasPrefix("-") {
        pendingLines.append(
          DiffLine(kind: .deletion, oldNumber: oldNumber, newNumber: nil, text: String(line.dropFirst()))
        )
        oldNumber += 1
      } else {
        let text = line.hasPrefix(" ") ? String(line.dropFirst()) : line
        pendingLines.append(
          DiffLine(kind: .context, oldNumber: oldNumber, newNumber: newNumber, text: text)
        )
        oldNumber += 1
        newNumber += 1
      }
    }
    flush()
    return FileDiff(path: path, isBinary: false, hunks: hunks)
  }

  private static func parseHunkHeader(
    _ line: String
  ) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)? {
    guard let match = line.firstMatch(of: /@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/) else {
      return nil
    }
    let oldStart = Int(match.1) ?? 0
    let oldCount = match.2.flatMap { Int($0) } ?? 1
    let newStart = Int(match.3) ?? 0
    let newCount = match.4.flatMap { Int($0) } ?? 1
    return (oldStart, oldCount, newStart, newCount)
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass.**

Run the same command as Step 3.
Expected: PASS (all 7 tests).

- [ ] **Step 6: Commit.**

```bash
git add supacode/Clients/Git/DiffModels.swift supacode/Clients/Git/UnifiedDiffParser.swift supacodeTests/UnifiedDiffParserTests.swift
git commit -m "Add diff models and UnifiedDiffParser"
```

---

## Task 2: ChangedFilesParser

**Files:**
- Create: `supacode/Clients/Git/ChangedFilesParser.swift`
- Test: `supacodeTests/ChangedFilesParserTests.swift`

**Interfaces:**
- Consumes: `DiffFileSummary`, `DiffFileStatus` (Task 1).
- Produces:
  `enum ChangedFilesParser { static func parse(nameStatus: String, numstat: String, untracked: [String]) -> [DiffFileSummary] }`

- [ ] **Step 1: Write the failing tests.**

Create `supacodeTests/ChangedFilesParserTests.swift`:
```swift
import Foundation
import Testing

@testable import supacode

struct ChangedFilesParserTests {
  @Test func mergesNameStatusAndNumstatForSimpleEdits() {
    let nameStatus = "M\tsrc/a.swift\nA\tsrc/b.swift\nD\tsrc/c.swift\n"
    let numstat = "3\t1\tsrc/a.swift\n10\t0\tsrc/b.swift\n0\t8\tsrc/c.swift\n"
    let result = ChangedFilesParser.parse(nameStatus: nameStatus, numstat: numstat, untracked: [])

    #expect(result.count == 3)

    let a = result[0]
    #expect(a.status == .modified)
    #expect(a.newPath == "src/a.swift")
    #expect(a.oldPath == nil)
    #expect(a.added == 3)
    #expect(a.removed == 1)

    let b = result[1]
    #expect(b.status == .added)
    #expect(b.newPath == "src/b.swift")
    #expect(b.added == 10)

    let c = result[2]
    #expect(c.status == .deleted)
    #expect(c.oldPath == "src/c.swift")
    #expect(c.newPath == nil)
    #expect(c.removed == 8)
  }

  @Test func parsesRenameWithSimilarityAndBracedNumstatPath() {
    let nameStatus = "R096\tlib/old.rb\tlib/new.rb\n"
    let numstat = "2\t1\tlib/{old.rb => new.rb}\n"
    let result = ChangedFilesParser.parse(nameStatus: nameStatus, numstat: numstat, untracked: [])

    #expect(result.count == 1)
    let r = result[0]
    #expect(r.status == .renamed)
    #expect(r.oldPath == "lib/old.rb")
    #expect(r.newPath == "lib/new.rb")
    #expect(r.added == 2)
    #expect(r.removed == 1)
  }

  @Test func parsesRenameWithCommonPrefixAndSuffixBraces() {
    // git numstat brace form with both prefix and suffix.
    let nameStatus = "R100\tsrc/old/file.swift\tsrc/new/file.swift\n"
    let numstat = "0\t0\tsrc/{old => new}/file.swift\n"
    let result = ChangedFilesParser.parse(nameStatus: nameStatus, numstat: numstat, untracked: [])
    let r = result[0]
    #expect(r.status == .renamed)
    #expect(r.newPath == "src/new/file.swift")
  }

  @Test func parsesPlainArrowNumstatPath() {
    let nameStatus = "R100\told.txt\tnew.txt\n"
    let numstat = "0\t0\told.txt => new.txt\n"
    let result = ChangedFilesParser.parse(nameStatus: nameStatus, numstat: numstat, untracked: [])
    #expect(result[0].newPath == "new.txt")
    #expect(result[0].added == 0)
  }

  @Test func marksBinaryFilesFromNumstatDashes() {
    let nameStatus = "M\tassets/logo.png\n"
    let numstat = "-\t-\tassets/logo.png\n"
    let result = ChangedFilesParser.parse(nameStatus: nameStatus, numstat: numstat, untracked: [])
    #expect(result[0].isBinary == true)
    #expect(result[0].added == 0)
    #expect(result[0].removed == 0)
  }

  @Test func appendsUntrackedFilesAsAdded() {
    let result = ChangedFilesParser.parse(
      nameStatus: "M\ta.swift\n",
      numstat: "1\t0\ta.swift\n",
      untracked: ["new1.swift", "dir/new2.swift"]
    )
    #expect(result.count == 3)
    #expect(result[1].status == .untracked)
    #expect(result[1].newPath == "new1.swift")
    #expect(result[1].oldPath == nil)
    #expect(result[2].newPath == "dir/new2.swift")
  }

  @Test func handlesEmptyInputs() {
    let result = ChangedFilesParser.parse(nameStatus: "", numstat: "", untracked: [])
    #expect(result.isEmpty)
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail.**

Run:
```bash
xcodebuild test -workspace supacode.xcworkspace -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/ChangedFilesParserTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation -parallel-testing-enabled NO
```
Expected: compile failure — `ChangedFilesParser` not defined.

- [ ] **Step 3: Implement `ChangedFilesParser`.**

Create `supacode/Clients/Git/ChangedFilesParser.swift`:
```swift
import Foundation

/// Merges `git diff --name-status --find-renames`, `git diff --numstat --find-renames`,
/// and a `git ls-files --others` untracked list into `[DiffFileSummary]`. Pure/synchronous.
enum ChangedFilesParser {
  private struct Counts {
    let added: Int
    let removed: Int
    let isBinary: Bool
  }

  static func parse(nameStatus: String, numstat: String, untracked: [String]) -> [DiffFileSummary] {
    let countsByPath = parseNumstat(numstat)
    var summaries: [DiffFileSummary] = []

    for rawLine in nameStatus.split(whereSeparator: \.isNewline) {
      let line = String(rawLine)
      guard !line.isEmpty else { continue }
      let fields = line.split(separator: "\t").map(String.init)
      guard let statusField = fields.first, let letter = statusField.first else { continue }
      // Local accessor: name-status lines have 2 fields (status + path) or 3 (rename/copy).
      func field(_ index: Int) -> String? { index < fields.count ? fields[index] : nil }

      let status: DiffFileStatus
      let oldPath: String?
      let newPath: String?
      switch letter {
      case "A":
        status = .added
        oldPath = nil
        newPath = field(1)
      case "D":
        status = .deleted
        oldPath = field(1)
        newPath = nil
      case "R":
        status = .renamed
        oldPath = field(1)
        newPath = field(2)
      case "C":
        status = .copied
        oldPath = field(1)
        newPath = field(2)
      default:
        // "M", "T" (type change), and anything else → treat as a modification.
        status = .modified
        oldPath = nil
        newPath = field(1)
      }

      let key = newPath ?? oldPath ?? ""
      let counts = countsByPath[key]
      summaries.append(
        DiffFileSummary(
          status: status,
          oldPath: oldPath,
          newPath: newPath,
          added: counts?.added ?? 0,
          removed: counts?.removed ?? 0,
          isBinary: counts?.isBinary ?? false
        )
      )
    }

    for path in untracked where !path.isEmpty {
      summaries.append(
        DiffFileSummary(status: .untracked, oldPath: nil, newPath: path, added: 0, removed: 0, isBinary: false)
      )
    }

    return summaries
  }

  private static func parseNumstat(_ numstat: String) -> [String: Counts] {
    var result: [String: Counts] = [:]
    for rawLine in numstat.split(whereSeparator: \.isNewline) {
      let line = String(rawLine)
      guard !line.isEmpty else { continue }
      // maxSplits 2 keeps the path (which may contain "=>") intact as the third field.
      let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
      guard fields.count == 3 else { continue }
      let addedField = fields[0]
      let removedField = fields[1]
      let isBinary = addedField == "-" || removedField == "-"
      let key = numstatNewPath(fields[2])
      result[key] = Counts(added: Int(addedField) ?? 0, removed: Int(removedField) ?? 0, isBinary: isBinary)
    }
    return result
  }

  /// Normalizes a numstat path field to the *new* path. Handles rename brace
  /// forms (`dir/{old => new}/file`, `dir/{old.rb => new.rb}`) and the plain
  /// `old => new` form; returns the input unchanged otherwise.
  private static func numstatNewPath(_ raw: String) -> String {
    if let open = raw.firstIndex(of: "{"), let close = raw.firstIndex(of: "}"), open < close {
      let prefix = raw[raw.startIndex..<open]
      let inside = raw[raw.index(after: open)..<close]
      let suffix = raw[raw.index(after: close)...]
      let newInside: Substring
      if let arrow = inside.range(of: " => ") {
        newInside = inside[arrow.upperBound...]
      } else {
        newInside = inside
      }
      return String(prefix) + String(newInside) + String(suffix)
    }
    if let arrow = raw.range(of: " => ") {
      return String(raw[arrow.upperBound...])
    }
    return raw
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass.**

Run the same command as Step 2.
Expected: PASS (all 7 tests).

- [ ] **Step 5: Commit.**

```bash
git add supacode/Clients/Git/ChangedFilesParser.swift supacodeTests/ChangedFilesParserTests.swift
git commit -m "Add ChangedFilesParser merging name-status, numstat, and untracked files"
```

---

## Task 3: GitClient.changedFiles + fileDiff + dependency wiring

**Files:**
- Modify: `supacode/Clients/Git/GitClient.swift` (add `GitOperation` cases near line 5-27; add methods near the existing `lineChanges` at line ~691)
- Modify: `supacode/Clients/Repositories/GitClientDependency.swift` (struct fields near line 50; `make` wiring near line 121)
- Test: `supacodeTests/GitClientDiffTests.swift`

**Interfaces:**
- Consumes: `UnifiedDiffParser.parse` (Task 1), `ChangedFilesParser.parse` (Task 2), `DiffScope`, `DiffFileSummary`, `FileDiff`, and the existing `runGit(operation:arguments:)`, `automaticWorktreeBaseRef(for:)`.
- Produces (on `GitClient`):
  - `nonisolated func changedFiles(at worktreeURL: URL, scope: DiffScope) async throws -> [DiffFileSummary]`
  - `nonisolated func fileDiff(at worktreeURL: URL, path filePath: String, scope: DiffScope) async throws -> FileDiff`
- Produces (on `GitClientDependency`):
  - `var changedFiles: @Sendable (URL, DiffScope) async throws -> [DiffFileSummary]`
  - `var fileDiff: @Sendable (URL, String, DiffScope) async throws -> FileDiff`

- [ ] **Step 1: Write the failing tests.**

Create `supacodeTests/GitClientDiffTests.swift`:
```swift
import Foundation
import Testing

@testable import SupacodeSettingsShared
@testable import supacode

actor DiffShellCallStore {
  private(set) var calls: [[String]] = []
  func record(_ arguments: [String]) { calls.append(arguments) }
}

struct GitClientDiffTests {
  /// Routes canned stdout per git subcommand so one mock serves multi-call methods.
  private func shell(
    store: DiffShellCallStore,
    nameStatus: String = "",
    numstat: String = "",
    lsFiles: String = "",
    diff: String = "",
    baseRef: String = ""
  ) -> ShellClient {
    ShellClient(
      run: { _, arguments, _ in
        await store.record(arguments)
        let stdout: String
        if arguments.contains("--name-status") {
          stdout = nameStatus
        } else if arguments.contains("--numstat") {
          stdout = numstat
        } else if arguments.contains("ls-files") {
          stdout = lsFiles
        } else if arguments.contains("diff") {
          stdout = diff
        } else {
          stdout = baseRef  // rev-parse / symbolic-ref used by base-ref resolution
        }
        return ShellOutput(stdout: stdout, stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
  }

  @Test func changedFilesUsesHeadForWorkingTreeVsHeadAndParsesResults() async throws {
    let store = DiffShellCallStore()
    let client = GitClient(
      shell: shell(
        store: store,
        nameStatus: "M\ta.swift\n",
        numstat: "4\t2\ta.swift\n",
        lsFiles: "untracked.swift\n"
      )
    )

    let files = try await client.changedFiles(at: URL(fileURLWithPath: "/tmp/wt"), scope: .workingTreeVsHead)

    #expect(files.count == 2)
    #expect(files[0].status == .modified)
    #expect(files[0].newPath == "a.swift")
    #expect(files[0].added == 4)
    #expect(files[0].removed == 2)
    #expect(files[1].status == .untracked)
    #expect(files[1].newPath == "untracked.swift")

    let calls = await store.calls
    let nameStatusCall = try #require(calls.first { $0.contains("--name-status") })
    #expect(nameStatusCall.contains("HEAD"))
    #expect(nameStatusCall.contains("--find-renames"))
    #expect(nameStatusCall.contains("-C"))
    #expect(nameStatusCall.contains("/tmp/wt"))
  }

  @Test func changedFilesStagedScopeUsesCachedAndSkipsUntracked() async throws {
    let store = DiffShellCallStore()
    let client = GitClient(shell: shell(store: store, nameStatus: "A\tx\n", numstat: "1\t0\tx\n"))

    let files = try await client.changedFiles(at: URL(fileURLWithPath: "/tmp/wt"), scope: .staged)

    #expect(files.count == 1)  // no untracked appended for staged scope
    let calls = await store.calls
    let nameStatusCall = try #require(calls.first { $0.contains("--name-status") })
    #expect(nameStatusCall.contains("--cached"))
    #expect(!calls.contains { $0.contains("ls-files") })
  }

  @Test func fileDiffParsesUnifiedDiffForTrackedFile() async throws {
    let store = DiffShellCallStore()
    let diffText = "@@ -1,1 +1,2 @@\n context\n+added\n"
    let client = GitClient(shell: shell(store: store, diff: diffText))

    let diff = try await client.fileDiff(at: URL(fileURLWithPath: "/tmp/wt"), path: "a.swift", scope: .workingTreeVsHead)

    #expect(diff.path == "a.swift")
    #expect(diff.hunks.count == 1)
    #expect(diff.hunks[0].lines.map(\.kind) == [.context, .addition])
    let calls = await store.calls
    let diffCall = try #require(calls.first { $0.contains("diff") && $0.contains("--") })
    #expect(diffCall.contains("a.swift"))
    #expect(diffCall.contains("HEAD"))
  }

  @Test func fileDiffSynthesizesAllAdditionsForUntrackedFile() async throws {
    // Empty git diff (untracked) + a real on-disk file → synthesized all-addition hunk.
    let fileManager = FileManager.default
    let worktree = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    try fileManager.createDirectory(at: worktree, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: worktree) }
    try "line one\nline two\n".write(to: worktree.appending(path: "new.txt"), atomically: true, encoding: .utf8)

    let store = DiffShellCallStore()
    let client = GitClient(shell: shell(store: store, diff: ""))  // empty diff output

    let diff = try await client.fileDiff(at: worktree, path: "new.txt", scope: .workingTreeVsHead)

    #expect(diff.isBinary == false)
    #expect(diff.hunks.count == 1)
    #expect(diff.hunks[0].lines.count == 2)
    #expect(diff.hunks[0].lines.allSatisfy { $0.kind == .addition })
    #expect(diff.hunks[0].lines[0].text == "line one")
    #expect(diff.hunks[0].lines[1].newNumber == 2)
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail.**

Run:
```bash
xcodebuild test -workspace supacode.xcworkspace -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/GitClientDiffTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation -parallel-testing-enabled NO
```
Expected: compile failure — `changedFiles` / `fileDiff` not defined on `GitClient`.

- [ ] **Step 3: Add the `GitOperation` cases.**

In `supacode/Clients/Git/GitClient.swift`, inside `enum GitOperation: String` (lines 5-27), add after the `fetchOrigin` case:
```swift
  case changedFiles = "changed_files"
  case fileDiff = "file_diff"
```

- [ ] **Step 4: Implement the two methods on `GitClient`.**

In `supacode/Clients/Git/GitClient.swift`, add immediately after the `lineChanges(at:)` method (ends ~line 706):
```swift
  nonisolated func changedFiles(at worktreeURL: URL, scope: DiffScope) async throws -> [DiffFileSummary] {
    let path = worktreeURL.path(percentEncoded: false)
    let base = await diffBaseArguments(for: scope, worktreeURL: worktreeURL)

    let nameStatus = try await runGit(
      operation: .changedFiles,
      arguments: ["-C", path, "diff", "--name-status", "--find-renames"] + base
    )
    let numstat = try await runGit(
      operation: .changedFiles,
      arguments: ["-C", path, "diff", "--numstat", "--find-renames"] + base
    )

    var untracked: [String] = []
    if scope != .staged {
      let others = try await runGit(
        operation: .changedFiles,
        arguments: ["-C", path, "ls-files", "--others", "--exclude-standard"]
      )
      untracked =
        others
        .split(whereSeparator: \.isNewline)
        .map { String($0).trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    }

    return ChangedFilesParser.parse(nameStatus: nameStatus, numstat: numstat, untracked: untracked)
  }

  nonisolated func fileDiff(at worktreeURL: URL, path filePath: String, scope: DiffScope) async throws -> FileDiff {
    let repoPath = worktreeURL.path(percentEncoded: false)
    let base = await diffBaseArguments(for: scope, worktreeURL: worktreeURL)
    let raw = try await runGit(
      operation: .fileDiff,
      arguments: ["-C", repoPath, "diff"] + base + ["--", filePath]
    )

    // An empty diff for a file in the changed list means it is untracked
    // (git diff doesn't show untracked content). Synthesize an all-addition
    // diff from the on-disk file rather than relying on `--no-index`, whose
    // nonzero exit code would surface as a thrown error.
    if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return syntheticAdditionDiff(filePath: filePath, worktreeURL: worktreeURL)
    }
    return UnifiedDiffParser.parse(raw, path: filePath)
  }

  /// Builds the `git diff` ref/flag arguments for a scope. `.workingTreeVsBase`
  /// resolves the base ref via `automaticWorktreeBaseRef`, falling back to HEAD.
  nonisolated private func diffBaseArguments(for scope: DiffScope, worktreeURL: URL) async -> [String] {
    switch scope {
    case .workingTreeVsHead:
      return ["HEAD"]
    case .staged:
      return ["--cached"]
    case .workingTreeVsBase:
      let base = await automaticWorktreeBaseRef(for: worktreeURL) ?? "HEAD"
      return [base]
    }
  }

  nonisolated private func syntheticAdditionDiff(filePath: String, worktreeURL: URL) -> FileDiff {
    let fileURL = worktreeURL.appending(path: filePath)
    guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
      // Unreadable as UTF-8 → treat as binary (no body).
      return FileDiff(path: filePath, isBinary: true, hunks: [])
    }
    var fileLines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if fileLines.last == "" { fileLines.removeLast() }  // drop trailing-newline artifact
    guard !fileLines.isEmpty else {
      return FileDiff(path: filePath, isBinary: false, hunks: [])
    }
    let lines = fileLines.enumerated().map { index, text in
      DiffLine(kind: .addition, oldNumber: nil, newNumber: index + 1, text: text)
    }
    let hunk = DiffHunk(
      header: "@@ -0,0 +1,\(fileLines.count) @@",
      oldStart: 0,
      oldCount: 0,
      newStart: 1,
      newCount: fileLines.count,
      lines: lines
    )
    return FileDiff(path: filePath, isBinary: false, hunks: [hunk])
  }
```

- [ ] **Step 5: Add the dependency closures.**

In `supacode/Clients/Repositories/GitClientDependency.swift`, add two fields to the `struct GitClientDependency` (after `lineChanges` at line 50):
```swift
  var changedFiles: @Sendable (URL, DiffScope) async throws -> [DiffFileSummary]
  var fileDiff: @Sendable (URL, String, DiffScope) async throws -> FileDiff
```

Then wire them in `make(shell:)` (after the `lineChanges` wiring at line 121):
```swift
      changedFiles: { try await GitClient(shell: shell).changedFiles(at: $0, scope: $1) },
      fileDiff: { try await GitClient(shell: shell).fileDiff(at: $0, path: $1, scope: $2) },
```

> `testValue` inherits `liveValue`, so these closures shell out for real in tests. Phase 2
> tests that need canned diffs will override `$0.gitClient.changedFiles` / `.fileDiff`
> per-test — no change to `testValue` is required here.

- [ ] **Step 6: Run the tests to verify they pass.**

Run the same command as Step 2.
Expected: PASS (all 4 tests).

- [ ] **Step 7: Run the full suite + lint/format to confirm no regressions.**

Run:
```bash
make test
make check
```
Expected: all tests pass; format/lint clean. Fix any swiftlint/swift-format findings before committing.

- [ ] **Step 8: Commit.**

```bash
git add supacode/Clients/Git/GitClient.swift supacode/Clients/Repositories/GitClientDependency.swift supacodeTests/GitClientDiffTests.swift
git commit -m "Add GitClient.changedFiles and fileDiff with dependency wiring"
```

---

## Self-Review (completed during planning)

- **Spec coverage (Phase 1 scope):** models ✅ (Task 1), `changedFiles` + `fileDiff` on both `GitClient` and `GitClientDependency` ✅ (Task 3), name-status + numstat merge incl. renames/untracked/binary ✅ (Task 2), `UnifiedDiffParser` incl. omitted counts / `\ No newline` / renames-skipped / binary ✅ (Task 1), base-ref resolution via `automaticWorktreeBaseRef` ✅ (Task 3), untracked-as-all-additions ✅ (Task 3). Phases 2–4 (FileViewer UI, MarkdownUI, terminal cmd-click) are deliberately separate plans.
- **Type consistency:** `changedFiles(at:scope:)` / `fileDiff(at:path:scope:)` signatures and the `DiffScope` / `DiffFileSummary` / `FileDiff` types are identical across the models file, the GitClient methods, the dependency closures, and every test. ✅
- **Placeholder scan:** no TBD/TODO; every code step has complete, directly-transcribable code. `ChangedFilesParser` uses a nested `field(_:)` accessor (no shared `Array` extension, so no duplicate-symbol risk); the `GitClientDiffTests` use only the real `GitClient(shell:)` initializer. ✅
- **Known assumption:** `fileDiff` treats an empty tracked-file diff as "untracked → synthesize." Valid because `fileDiff` is only ever called for files already in the `changedFiles` list. Documented inline.

---

## Next phases (separate plans, written when reached)
- **Phase 2:** `Features/FileViewer` reducer/state + `SourceView` (plain monospaced) + `DiffView` + `DiffFileListView`; mount as a collapsible side pane via `SplitView` in `WorktreeDetailView`.
- **Phase 3:** MarkdownUI dependency (via `Tuist/Package.swift` + `Project.swift`) + `MarkdownPreviewView` + mode-by-extension + theming.
- **Phase 4:** ghostty `RepeatableLink.parseCLI` patch + `link` config line + bridge resolve/validate/route + `onOpenWorktreeFile` callback wiring.
