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
    let rawCandidate: URL =
      pathPart.hasPrefix("/")
      ? URL(filePath: pathPart)
      : base.appending(path: pathPart)
    // Resolve symlinks on BOTH sides before the containment check: `standardizedFileURL`
    // only canonicalizes `.`/`..`, NOT symlinks, so a symlink inside the worktree pointing
    // outside would otherwise pass the string-prefix check. Resolving both keeps containment
    // honest and stays consistent on macOS where the worktree root may itself sit under a
    // symlinked prefix (e.g. /var -> /private/var, /tmp -> /private/tmp).
    let candidate = rawCandidate.standardizedFileURL.resolvingSymlinksInPath()
    let root = worktreeRoot.standardizedFileURL.resolvingSymlinksInPath()
    let rootPath = root.path(percentEncoded: false)
    let candidatePath = candidate.path(percentEncoded: false)
    // Containment: candidate must be strictly under the root (not the root itself).
    let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    guard candidatePath.hasPrefix(rootPrefix) else { return nil }
    // Must be an existing regular file (not a directory).
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: candidatePath, isDirectory: &isDirectory), !isDirectory.boolValue
    else { return nil }

    let relative = String(candidatePath.dropFirst(rootPrefix.count))
    guard !relative.isEmpty else { return nil }
    return Resolved(relativePath: relative, line: line)
  }

  /// Splits a trailing `:line` or `:line:col` suffix off a path token.
  private static func splitLineSuffix(_ token: String) -> (path: String, line: Int?) {
    let parts = token.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    guard parts.count >= 2 else { return (token, nil) }
    // `path:line`
    if parts.count == 2, let line = Int(parts[1]) {
      return (parts[0], line)
    }
    // `path:line:col`
    if parts.count == 3, Int(parts[2]) != nil, let line = Int(parts[1]) {
      return (parts[0], line)
    }
    return (token, nil)  // not a line-suffix shape → treat whole token as path
  }
}
