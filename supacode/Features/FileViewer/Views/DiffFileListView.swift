import SwiftUI

/// The changed-files list. Pure renderer: parent supplies the files, the
/// selected path, and a tap handler that drives the viewer.
struct DiffFileListView: View {
  let files: [DiffFileSummary]
  let selectedPath: String?
  let onTap: (String) -> Void

  var body: some View {
    // Native List selection (not a per-row Button): a Button inside a scrolling
    // List loses the tap that lands during scroll deceleration, so a quick click
    // right after scrolling did nothing. List selection hit-tests the whole row
    // reliably and also drives the row highlight.
    List(selection: selectionBinding) {
      ForEach(files, id: \.id) { file in
        HStack(spacing: 6) {
          Image(systemName: Self.symbol(for: file.status))
            .foregroundStyle(Self.color(for: file.status))
            .frame(width: 16)
            .accessibilityLabel(Self.accessibilityLabel(for: file.status))
          Text(Self.displayName(file))
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer(minLength: 8)
          if file.isBinary {
            Text("bin").font(.caption).foregroundStyle(.secondary)
          } else {
            Text("+\(file.added)").font(.caption.monospaced()).foregroundStyle(.green)
            Text("-\(file.removed)").font(.caption.monospaced()).foregroundStyle(.red)
          }
        }
        .tag(file.id)
        .help(Self.displayName(file))
      }
    }
    .listStyle(.sidebar)
  }

  /// Reads the selected path for the highlight; on click, forwards the new
  /// selection to `onTap` (ignoring a clear-to-nil, which a click can't produce).
  private var selectionBinding: Binding<String?> {
    Binding(get: { selectedPath }, set: { if let id = $0 { onTap(id) } })
  }

  private static func displayName(_ file: DiffFileSummary) -> String {
    switch file.status {
    case .renamed, .copied:
      "\(file.oldPath ?? "?") → \(file.newPath ?? "?")"
    default:
      file.newPath ?? file.oldPath ?? "?"
    }
  }

  private static func symbol(for status: DiffFileStatus) -> String {
    switch status {
    case .added: "plus.circle"
    case .modified: "pencil.circle"
    case .deleted: "minus.circle"
    case .renamed: "arrow.right.circle"
    case .copied: "doc.on.doc"
    case .untracked: "questionmark.circle"
    }
  }

  private static func color(for status: DiffFileStatus) -> Color {
    switch status {
    case .added, .untracked: .green
    case .modified, .renamed, .copied: .secondary
    case .deleted: .red
    }
  }

  private static func accessibilityLabel(for status: DiffFileStatus) -> String {
    switch status {
    case .added: "Added"
    case .modified: "Modified"
    case .deleted: "Deleted"
    case .renamed: "Renamed"
    case .copied: "Copied"
    case .untracked: "Untracked"
    }
  }
}
