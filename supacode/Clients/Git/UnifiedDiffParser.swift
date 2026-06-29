import Foundation

/// Parses raw `git diff` output for a *single file* into a structured `FileDiff`.
/// Pure and synchronous so it is unit-testable without shelling out.
enum UnifiedDiffParser {
  /// The `@@` hunk-header bounds, grouped to avoid a large (>2 member) tuple.
  private struct HunkBounds {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
  }

  static func parse(_ raw: String, path: String) -> FileDiff {
    let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    if lines.contains(where: { $0.hasPrefix("Binary files") || $0.hasPrefix("GIT binary patch") }) {
      return FileDiff(path: path, isBinary: true, hunks: [])
    }

    var hunks: [DiffHunk] = []
    var pendingHeader: String?
    var pendingBounds: HunkBounds?
    var pendingLines: [DiffLine] = []
    var oldNumber = 0
    var newNumber = 0

    func flush() {
      guard let pendingHeader, let pendingBounds else { return }
      hunks.append(
        DiffHunk(
          header: pendingHeader,
          oldStart: pendingBounds.oldStart,
          oldCount: pendingBounds.oldCount,
          newStart: pendingBounds.newStart,
          newCount: pendingBounds.newCount,
          lines: pendingLines
        )
      )
      pendingLines = []
    }

    for line in lines {
      if line.hasPrefix("@@") {
        flush()
        if let bounds = parseHunkHeader(line) {
          pendingHeader = line
          pendingBounds = bounds
          oldNumber = bounds.oldStart
          newNumber = bounds.newStart
        } else {
          pendingHeader = nil
          pendingBounds = nil
        }
        continue
      }

      // Skip anything before the first hunk header (diff --git, index, ---, +++)
      // and the trailing empty string produced by a final newline.
      guard pendingBounds != nil, !line.isEmpty else { continue }

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

  private static func parseHunkHeader(_ line: String) -> HunkBounds? {
    guard let match = line.firstMatch(of: /@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/) else {
      return nil
    }
    return HunkBounds(
      oldStart: Int(match.1) ?? 0,
      oldCount: match.2.flatMap { Int($0) } ?? 1,
      newStart: Int(match.3) ?? 0,
      newCount: match.4.flatMap { Int($0) } ?? 1
    )
  }
}
