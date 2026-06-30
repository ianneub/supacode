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

  @Test func stripsCarriageReturnFromCRLFContent() {
    let raw = "@@ -1,1 +1,1 @@\r\n-old\r\n+new\r\n"
    let hunk = UnifiedDiffParser.parse(raw, path: "a").hunks[0]
    #expect(hunk.lines.map(\.kind) == [.deletion, .addition])
    #expect(hunk.lines[0].text == "old")
    #expect(hunk.lines[1].text == "new")
  }
}
