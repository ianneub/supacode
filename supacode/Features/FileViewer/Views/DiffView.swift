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

  var body: some View {
    if fileDiff.isBinary {
      ContentUnavailableView("Binary file", systemImage: "doc.badge.gearshape")
    } else if fileDiff.hunks.isEmpty {
      ContentUnavailableView("No changes", systemImage: "equal")
    } else {
      ScrollView([.vertical, .horizontal]) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(Array(fileDiff.hunks.enumerated()), id: \.offset) { _, hunk in
            Text(hunk.header)
              .font(.body.monospaced())
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 2)
              .background(.quaternary)
            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
              DiffLineRow(line: line, showsOld: showsOld, showsNew: showsNew, digitCount: digitCount)
            }
          }
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
    .background(rowBackground)
  }

  /// A hidden run of digits reserves exactly the right column width at any Dynamic
  /// Type size (monospaced → every digit is the same advance), with the real number
  /// right-aligned over it. No magic per-digit constants, and numbers never wrap.
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
