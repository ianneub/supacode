import SwiftUI

/// Plain, read-only, monospaced source rendering. Syntax highlighting is a
/// deliberate future enhancement (not this pass).
struct SourceView: View {
  let text: String

  var body: some View {
    ScrollView([.vertical, .horizontal]) {
      Text(text.isEmpty ? " " : text)
        .font(.body.monospaced())
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .padding(8)
    }
  }
}
