import AppKit
import SwiftUI

/// Inline unified-diff renderer: old/new line-number gutters + add/delete/context
/// coloring from system semantic colors. Lazy so large diffs don't render at once.
struct DiffView: View {
  let fileDiff: FileDiff

  /// A gutter only renders if that side actually has line numbers, so an added
  /// file doesn't reserve a permanently-empty "old" column (and vice versa).
  private var showsOld: Bool {
    fileDiff.hunks.contains { $0.lines.contains { $0.oldNumber != nil } }
  }
  private var showsNew: Bool {
    fileDiff.hunks.contains { $0.lines.contains { $0.newNumber != nil } }
  }

  /// Digits in the largest line number — the gutter sizes itself to exactly this
  /// many monospaced digits so numbers hug the text instead of sitting behind a
  /// fixed, oversized column.
  private var digitCount: Int {
    let maxNumber = fileDiff.hunks
      .lazy
      .flatMap(\.lines)
      .reduce(0) { max($0, max($1.oldNumber ?? 0, $1.newNumber ?? 0)) }
    return max(2, String(maxNumber).count)
  }

  /// Measured pixel width of the widest rendered row — gutters plus the longest
  /// line of code. Used as the stack's minimum width so long lines extend into the
  /// horizontal scroll; the pane width takes over when the diff is narrower than
  /// the pane (so rows still fill the full width). Measured once per file (body
  /// only re-runs when `fileDiff` changes), not on scroll. `utf8.count` (not
  /// grapheme `count`) picks the longest line cheaply on big diffs.
  private var contentWidth: CGFloat {
    let font = NSFont.monospacedSystemFont(
      ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
    let digitW = ("0" as NSString).size(withAttributes: [.font: font]).width
    let longest = fileDiff.hunks.lazy.flatMap(\.lines).max { $0.text.utf8.count < $1.text.utf8.count }?.text ?? ""
    let textW = ("+ " + longest as NSString).size(withAttributes: [.font: font]).width
    let gutters = CGFloat((showsOld ? 1 : 0) + (showsNew ? 1 : 0))
    // 4 (row leading) + per-gutter (digits + 6 pad) + 8 (text leading) + text + slack
    return 4 + gutters * (digitW * CGFloat(digitCount) + 6) + 8 + textW + 16
  }

  var body: some View {
    if fileDiff.isBinary {
      ContentUnavailableView("Binary file", systemImage: "doc.badge.gearshape")
    } else if fileDiff.hunks.isEmpty {
      ContentUnavailableView("No changes", systemImage: "equal")
    } else {
      // Nested single-axis scroll views, NOT one both-axes ScrollView around a
      // LazyVStack. A LazyVStack can't resolve its cross-axis inside a both-axes
      // scroll, so it mis-estimates geometry (diff shoved right, stray gaps between
      // hunks); a plain VStack lays out correctly but renders every row eagerly,
      // which stalls the main thread for ~1–2s on a thousand-line file. Here the
      // inner vertical ScrollView keeps the LazyVStack on its supported single axis
      // (only on-screen rows realize → instant), while the outer horizontal
      // ScrollView carries long lines. The content is pinned to a definite size:
      // `max(contentWidth, pane width)` fills the pane yet grows for long lines, and
      // `minHeight: pane height` keeps a short diff flush at the top instead of
      // letting the ScrollView center it.
      GeometryReader { proxy in
        ScrollView(.horizontal) {
          ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
              ForEach(Array(fileDiff.hunks.enumerated()), id: \.offset) { _, hunk in
                Text(hunk.header)
                  .font(.body.monospaced())
                  .foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.vertical, 2)
                  .padding(.leading, 4)
                  .background(.quaternary)
                ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                  DiffLineRow(line: line, showsOld: showsOld, showsNew: showsNew, digitCount: digitCount)
                }
              }
            }
            .frame(width: max(contentWidth, proxy.size.width), alignment: .leading)
            .frame(minHeight: proxy.size.height, alignment: .topLeading)
          }
          // Bound the inner vertical scroll to the pane height so it actually
          // scrolls (and stays lazy) instead of growing to its full content height.
          .frame(height: proxy.size.height)
        }
      }
      .textSelection(.enabled)
    }
  }
}

private struct DiffLineRow: View {
  let line: DiffLine
  let showsOld: Bool
  let showsNew: Bool
  let digitCount: Int

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      if showsOld { gutter(line.oldNumber) }
      if showsNew { gutter(line.newNumber) }
      Text(prefix + line.text)
        .font(.body.monospaced())
        .foregroundStyle(textColor)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.leading, 8)
    }
    .padding(.leading, 4)
    // Fill the stack's full width so the row tint spans the pane, not just the text.
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(rowBackground)
  }

  /// A hidden run of digits reserves exactly the right column width at any Dynamic
  /// Type size (monospaced → every digit is the same advance), with the real number
  /// right-aligned over it. No magic per-digit constants, and numbers never wrap.
  ///
  /// `fixedSize()` makes the gutter rigid: without it, the adjacent `fixedSize`
  /// code text on a long line claims all the row width and starves this
  /// intrinsic-sized column to zero, dropping the line number on long rows.
  private func gutter(_ number: Int?) -> some View {
    Text(String(repeating: "0", count: digitCount))
      .font(.body.monospaced())
      .hidden()
      .overlay(alignment: .trailing) {
        Text(number.map(String.init) ?? "")
          .font(.body.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .fixedSize()
      .padding(.leading, 6)
  }

  private var prefix: String {
    switch line.kind {
    case .addition: "+ "
    case .deletion: "- "
    case .context: "  "
    case .noNewlineMarker: ""
    }
  }

  private var textColor: Color {
    switch line.kind {
    case .addition: .green
    case .deletion: .red
    case .context: .primary
    case .noNewlineMarker: .secondary
    }
  }

  private var rowBackground: Color {
    switch line.kind {
    case .addition: Color.green.opacity(0.12)
    case .deletion: Color.red.opacity(0.12)
    case .context, .noNewlineMarker: .clear
    }
  }
}
