import AppKit
import SupacodeSettingsShared
import Testing

@testable import supacode

@MainActor
struct ToggleFileViewerShortcutTests {
  private func keyEvent(_ ignoringModifiers: String, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: modifiers,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: ignoringModifiers,
      charactersIgnoringModifiers: ignoringModifiers,
      isARepeat: false,
      keyCode: 14
    )!
  }

  @Test func matchesCommandE() {
    #expect(SupacodeAppDelegate.event(keyEvent("e", [.command]), matches: AppShortcuts.toggleFileViewer))
  }

  @Test func rejectsCommandShiftE() {
    // ⌘⇧E is "Reveal in Sidebar"; it must not also trigger the file-viewer toggle.
    #expect(!SupacodeAppDelegate.event(keyEvent("e", [.command, .shift]), matches: AppShortcuts.toggleFileViewer))
  }

  @Test func rejectsDifferentKey() {
    #expect(!SupacodeAppDelegate.event(keyEvent("f", [.command]), matches: AppShortcuts.toggleFileViewer))
  }

  @Test func ignoresIrrelevantModifierFlags() {
    // Stray flags (numeric pad, function) on the event don't break the match.
    #expect(
      SupacodeAppDelegate.event(keyEvent("e", [.command, .numericPad]), matches: AppShortcuts.toggleFileViewer)
    )
  }
}
