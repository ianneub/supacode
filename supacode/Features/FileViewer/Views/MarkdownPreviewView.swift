import MarkdownUI
import SwiftUI

/// Renders markdown source text as formatted, themed content. Read-only.
struct MarkdownPreviewView: View {
  let text: String

  var body: some View {
    ScrollView {
      Markdown(text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .padding(12)
    }
  }
}
