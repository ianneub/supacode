import Testing

@testable import supacode

struct ChangedFilesParserTests {
  @Test func mergesNameStatusAndNumstatForSimpleEdits() {
    let nameStatus = "M\tsrc/a.swift\nA\tsrc/b.swift\nD\tsrc/c.swift\n"
    let numstat = "3\t1\tsrc/a.swift\n10\t0\tsrc/b.swift\n0\t8\tsrc/c.swift\n"
    let result = ChangedFilesParser.parse(nameStatus: nameStatus, numstat: numstat, untracked: [])

    #expect(result.count == 3)

    let fileA = result[0]
    #expect(fileA.status == .modified)
    #expect(fileA.newPath == "src/a.swift")
    #expect(fileA.oldPath == nil)
    #expect(fileA.added == 3)
    #expect(fileA.removed == 1)

    let fileB = result[1]
    #expect(fileB.status == .added)
    #expect(fileB.newPath == "src/b.swift")
    #expect(fileB.added == 10)

    let fileC = result[2]
    #expect(fileC.status == .deleted)
    #expect(fileC.oldPath == "src/c.swift")
    #expect(fileC.newPath == nil)
    #expect(fileC.removed == 8)
  }

  @Test func parsesRenameWithSimilarityAndBracedNumstatPath() {
    let nameStatus = "R096\tlib/old.rb\tlib/new.rb\n"
    let numstat = "2\t1\tlib/{old.rb => new.rb}\n"
    let result = ChangedFilesParser.parse(nameStatus: nameStatus, numstat: numstat, untracked: [])

    #expect(result.count == 1)
    let renamed = result[0]
    #expect(renamed.status == .renamed)
    #expect(renamed.oldPath == "lib/old.rb")
    #expect(renamed.newPath == "lib/new.rb")
    #expect(renamed.added == 2)
    #expect(renamed.removed == 1)
  }

  @Test func parsesRenameWithCommonPrefixAndSuffixBraces() {
    // git numstat brace form with both prefix and suffix.
    let nameStatus = "R100\tsrc/old/file.swift\tsrc/new/file.swift\n"
    let numstat = "0\t0\tsrc/{old => new}/file.swift\n"
    let result = ChangedFilesParser.parse(nameStatus: nameStatus, numstat: numstat, untracked: [])
    let renamed = result[0]
    #expect(renamed.status == .renamed)
    #expect(renamed.newPath == "src/new/file.swift")
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

  @Test func parsesCopiedStatus() {
    let nameStatus = "C100\tsrc/orig.swift\tsrc/copy.swift\n"
    let numstat = "0\t0\tsrc/copy.swift\n"
    let result = ChangedFilesParser.parse(nameStatus: nameStatus, numstat: numstat, untracked: [])
    #expect(result.count == 1)
    #expect(result[0].status == .copied)
    #expect(result[0].oldPath == "src/orig.swift")
    #expect(result[0].newPath == "src/copy.swift")
  }
}
