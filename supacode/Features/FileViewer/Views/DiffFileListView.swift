import SwiftUI

/// The changed-files list. Pure renderer: parent supplies the files, the
/// selected path, and a tap handler that drives the viewer.
struct DiffFileListView: View {
  let files: [DiffFileSummary]
  let selectedPath: String?
  let onTap: (String) -> Void

  var body: some View {
    List(files, id: \.id, selection: .constant(selectedPath)) { file in
      Button {
        onTap(file.id)
      } label: {
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
      }
      .buttonStyle(.plain)
      .help(Self.displayName(file))
    }
    .listStyle(.sidebar)
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
