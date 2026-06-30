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
