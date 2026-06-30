import AppKit
import SwiftUI

/// Inline unified-diff renderer: old/new line-number gutters + add/delete/context
/// coloring from system semantic colors.
///
/// Rows render in a `List` (NSTableView-backed): genuinely lazy — only on-screen
/// rows realize, so even a thousand-line diff opens instantly — and, unlike
/// `LazyVStack`, it measures real row heights so there are no estimation gaps. The
/// List sits in a horizontal `ScrollView` pinned to `max(contentWidth, paneWidth)`
/// so long lines scroll sideways while short diffs still fill the pane width.
struct DiffView: View {
  let fileDiff: FileDiff

  /// One List row: a hunk header or a diff line. `id` is the flattened index, which
  /// is stable for a given `fileDiff`.
  private struct Row: Identifiable {
    let id: Int
    enum Kind {
      case header(String)
      case line(DiffLine)
    }
    let kind: Kind
  }

  /// Flattened hunk headers + lines, in display order.
  private var rows: [Row] {
    var out: [Row] = []
    out.reserveCapacity(fileDiff.hunks.reduce(0) { $0 + 1 + $1.lines.count })
    var id = 0
    for hunk in fileDiff.hunks {
      out.append(Row(id: id, kind: .header(hunk.header)))
      id += 1
      for line in hunk.lines {
        out.append(Row(id: id, kind: .line(line)))
        id += 1
      }
    }
    return out
  }

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

  /// The monospaced body font the rows render in (also used to measure widths/heights).
  private var rowFont: NSFont {
    NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
  }

  /// Fixed, uniform row height = one monospaced line. Every row is pinned to this so
  /// the List/NSTableView can stay lazy: self-sizing rows force it to lay out every
  /// row's text up front, which stalls a large diff for ~1.5s. Uniform heights keep
  /// it to the on-screen rows. (It also removes the inter-line gap the default min
  /// height added.)
  private var rowHeight: CGFloat {
    NSLayoutManager().defaultLineHeight(for: rowFont)
  }

  /// Measured pixel width of the widest rendered row — gutters plus the longest
  /// line of code. The List is pinned to this (or the pane width, whichever is
  /// larger) so long lines extend into the horizontal scroll while a narrow diff
  /// still fills the pane. Measured once per file (body only re-runs when
  /// `fileDiff` changes), not on scroll. `utf8.count` (not grapheme `count`) picks
  /// the longest line cheaply on big diffs.
  private var contentWidth: CGFloat {
    let digitW = ("0" as NSString).size(withAttributes: [.font: rowFont]).width
    let longest = fileDiff.hunks.lazy.flatMap(\.lines).max { $0.text.utf8.count < $1.text.utf8.count }?.text ?? ""
    let textW = ("+ " + longest as NSString).size(withAttributes: [.font: rowFont]).width
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
      GeometryReader { proxy in
        // List = NSTableView: lazy AND correct row heights (no LazyVStack gaps). The
        // outer horizontal ScrollView carries long lines; the List width is pinned so
        // short diffs fill the pane and long ones scroll sideways.
        ScrollView(.horizontal) {
          List(rows) { row in
            rowView(row)
              // Uniform fixed height keeps the List lazy (see `rowHeight`) and removes
              // the default inter-row gap.
              .frame(height: rowHeight)
              .listRowInsets(EdgeInsets())
              .listRowSeparator(.hidden)
              .listRowBackground(Color.clear)
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
          .environment(\.defaultMinListRowHeight, rowHeight)
          .frame(width: max(contentWidth, proxy.size.width), height: proxy.size.height)
        }
      }
    }
  }

  @ViewBuilder private func rowView(_ row: Row) -> some View {
    switch row.kind {
    case .header(let header):
      Text(header)
        .font(.body.monospaced())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.leading, 4)
        .background(.quaternary)
    case .line(let line):
      DiffLineRow(line: line, showsOld: showsOld, showsNew: showsNew, digitCount: digitCount)
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
        .textSelection(.enabled)
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
