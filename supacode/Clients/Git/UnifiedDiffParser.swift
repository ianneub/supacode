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
