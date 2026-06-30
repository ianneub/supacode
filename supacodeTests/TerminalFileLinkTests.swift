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
    let root = try makeWorktree()
    defer { try? FileManager.default.removeItem(at: root) }
    let resolved = TerminalFileLink.resolve(rawToken: "src/a.swift", pwd: root.path, worktreeRoot: root)
    #expect(resolved == TerminalFileLink.Resolved(relativePath: "src/a.swift", line: nil))
  }

  @Test func stripsLineAndColumnSuffix() throws {
    let root = try makeWorktree()
    defer { try? FileManager.default.removeItem(at: root) }
    let resolved = TerminalFileLink.resolve(rawToken: "src/a.swift:42:7", pwd: root.path, worktreeRoot: root)
    #expect(resolved == TerminalFileLink.Resolved(relativePath: "src/a.swift", line: 42))
  }

  @Test func rejectsPathEscapingWorktree() throws {
    let root = try makeWorktree()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(TerminalFileLink.resolve(rawToken: "../etc/passwd", pwd: root.path, worktreeRoot: root) == nil)
  }

  @Test func rejectsNonexistentPath() throws {
    let root = try makeWorktree()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(TerminalFileLink.resolve(rawToken: "src/missing.swift", pwd: root.path, worktreeRoot: root) == nil)
  }

  @Test func pwdNilFallsBackToWorktreeRoot() throws {
    let root = try makeWorktree()
    defer { try? FileManager.default.removeItem(at: root) }
    let resolved = TerminalFileLink.resolve(rawToken: "README.md", pwd: nil, worktreeRoot: root)
    #expect(resolved == TerminalFileLink.Resolved(relativePath: "README.md", line: nil))
  }

  // Additional edge-case coverage for this security-critical resolver

  @Test func resolvesAbsoluteInWorktreePath() throws {
    let root = try makeWorktree()
    defer { try? FileManager.default.removeItem(at: root) }
    let absPath = root.appending(path: "src/a.swift").path
    let resolved = TerminalFileLink.resolve(rawToken: absPath, pwd: nil, worktreeRoot: root)
    #expect(resolved == TerminalFileLink.Resolved(relativePath: "src/a.swift", line: nil))
  }

  @Test func rejectsAbsolutePathOutsideWorktree() throws {
    let root = try makeWorktree()
    defer { try? FileManager.default.removeItem(at: root) }
    // /etc/passwd is outside any temp worktree
    #expect(TerminalFileLink.resolve(rawToken: "/etc/passwd", pwd: root.path, worktreeRoot: root) == nil)
  }

  @Test func stripsLineSuffixWhenBaseFileExists() throws {
    // "src/a.swift:42" — the file "src/a.swift:42" doesn't exist but "src/a.swift" does
    let root = try makeWorktree()
    defer { try? FileManager.default.removeItem(at: root) }
    let resolved = TerminalFileLink.resolve(rawToken: "src/a.swift:42", pwd: root.path, worktreeRoot: root)
    #expect(resolved == TerminalFileLink.Resolved(relativePath: "src/a.swift", line: 42))
  }

  @Test func rejectsEmptyToken() throws {
    let root = try makeWorktree()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(TerminalFileLink.resolve(rawToken: "", pwd: root.path, worktreeRoot: root) == nil)
    #expect(TerminalFileLink.resolve(rawToken: "   ", pwd: root.path, worktreeRoot: root) == nil)
  }

  @Test func rejectsPrefixMatchFalsePositive() throws {
    // A worktree at /tmp/wt should NOT accept /tmp/wt-evil/file even if /tmp/wt-evil/file exists
    let root = FileManager.default.temporaryDirectory.appending(path: "wt-" + UUID().uuidString)
    let evil = FileManager.default.temporaryDirectory.appending(path: root.lastPathComponent + "-evil")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: evil, withIntermediateDirectories: true)
    let evilFile = evil.appending(path: "secret.txt")
    try "secret".write(to: evilFile, atomically: true, encoding: .utf8)
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: evil)
    }
    let standardizedRoot = root.standardizedFileURL
    #expect(
      TerminalFileLink.resolve(rawToken: evilFile.path, pwd: standardizedRoot.path, worktreeRoot: standardizedRoot)
        == nil
    )
  }

  @Test func pwdEmptyStringFallsBackToWorktreeRoot() throws {
    let root = try makeWorktree()
    defer { try? FileManager.default.removeItem(at: root) }
    let resolved = TerminalFileLink.resolve(rawToken: "README.md", pwd: "", worktreeRoot: root)
    #expect(resolved == TerminalFileLink.Resolved(relativePath: "README.md", line: nil))
  }

  @Test func rejectsSymlinkEscapingWorktree() throws {
    let root = try makeWorktree()
    defer { try? FileManager.default.removeItem(at: root) }
    // An out-of-worktree target the symlink points at.
    let outside = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".txt")
    try "secret".write(to: outside, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: outside) }
    // A symlink INSIDE the worktree pointing OUTSIDE it.
    let link = root.appending(path: "src/escape.txt")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    // String-prefix containment would accept "src/escape.txt"; symlink resolution must reject it.
    #expect(TerminalFileLink.resolve(rawToken: "src/escape.txt", pwd: root.path, worktreeRoot: root) == nil)
  }

  @Test func rejectsDirectoryToken() throws {
    let root = try makeWorktree()
    defer { try? FileManager.default.removeItem(at: root) }
    // `src` exists but is a directory, not a file.
    #expect(TerminalFileLink.resolve(rawToken: "src", pwd: root.path, worktreeRoot: root) == nil)
  }
}
