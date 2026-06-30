import SwiftUI

/// Inline unified-diff renderer: old/new line-number gutters + add/delete/context
/// coloring from system semantic colors. Lazy so large diffs don't render at once.
struct DiffView: View {
  let fileDiff: FileDiff

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
              DiffLineRow(line: line)
            }
          }
        }
        .padding(.vertical, 4)
      }
      .textSelection(.enabled)
    }
  }
}

private struct DiffLineRow: View {
  let line: DiffLine

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      gutter(line.oldNumber)
      gutter(line.newNumber)
      Text(prefix + line.text)
        .font(.body.monospaced())
        .foregroundStyle(textColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }
    .padding(.horizontal, 4)
    .background(rowBackground)
  }

  private func gutter(_ number: Int?) -> some View {
    Text(number.map(String.init) ?? "")
      .font(.body.monospaced())
      .foregroundStyle(.secondary)
      .frame(width: 44, alignment: .trailing)
      .padding(.trailing, 6)
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
