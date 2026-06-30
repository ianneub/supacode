import SwiftUI

/// Plain, read-only, monospaced source rendering. Syntax highlighting is a
/// deliberate future enhancement (not this pass).
struct SourceView: View {
  let text: String

  var body: some View {
    // GeometryReader + minWidth/minHeight pins the text flush to the top-left:
    // a both-axes ScrollView otherwise centers content shorter than the viewport
    // (same fix as DiffView). minWidth fills the pane; the text still grows past
    // it for long lines (horizontal scroll).
    GeometryReader { proxy in
      ScrollView([.vertical, .horizontal]) {
        Text(text.isEmpty ? " " : text)
          .font(.body.monospaced())
          .foregroundStyle(.primary)
          .textSelection(.enabled)
          .padding(8)
          .frame(
            minWidth: proxy.size.width,
            minHeight: proxy.size.height,
            alignment: .topLeading
          )
      }
    }
  }
}
