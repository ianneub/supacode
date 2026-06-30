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

    let diff = try await client.fileDiff(
      at: URL(fileURLWithPath: "/tmp/wt"), path: "a.swift", scope: .workingTreeVsHead)

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
