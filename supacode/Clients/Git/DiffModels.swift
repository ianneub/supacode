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
  case staged  // staged changes (--cached)
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
