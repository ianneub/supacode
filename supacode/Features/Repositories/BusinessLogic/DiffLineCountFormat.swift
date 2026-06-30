import Foundation

/// Shared abbreviation for diff line counts shown in the sidebar and the worktree
/// toolbar, so both read the same: `999` stays `999`, `1000` → `1k`, `1500` →
/// `1.5k`, `12345` → `12k`.
enum DiffLineCountFormat {
  static func abbreviated(_ count: Int) -> String {
    guard count >= 1000 else { return String(count) }
    let thousands = Double(count) / 1000
    if thousands >= 10 {
      return "\(Int(thousands.rounded()))k"
    }
    // One decimal place, dropping a trailing `.0` (1000 → "1k", 1500 → "1.5k").
    let rounded = (thousands * 10).rounded() / 10
    return rounded == rounded.rounded() ? "\(Int(rounded))k" : "\(rounded)k"
  }
}
