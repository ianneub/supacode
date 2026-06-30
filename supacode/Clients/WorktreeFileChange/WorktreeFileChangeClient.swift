import ComposableArchitecture
import Foundation

/// Emits a tick whenever the file viewer should re-check a worktree's diff while
/// the pane is open. The live implementation polls on a fixed cadence — the git
/// HEAD watcher (`WorktreeInfoWatcherManager`) only fires on commits/checkouts,
/// not on working-tree edits, so a save wouldn't otherwise refresh the diff.
///
/// Modeled as a stream so it stays trivially testable: the test value is an
/// already-finished stream, so a `for await` over it completes immediately and
/// never leaves a long-running effect in flight.
struct WorktreeFileChangeClient: Sendable {
  /// A stream of "re-check now" ticks for the given worktree. Never finishes on
  /// its own in the live implementation; the consumer cancels it by tearing down
  /// the effect (closing the pane).
  var ticks: @Sendable (_ worktreeURL: URL) -> AsyncStream<Void>
}

extension WorktreeFileChangeClient: DependencyKey {
  static var liveValue: WorktreeFileChangeClient {
    Self(ticks: { _ in
      AsyncStream { continuation in
        let task = Task {
          let clock = ContinuousClock()
          // Poll cadence — snappy enough to feel live without spawning git constantly.
          while !Task.isCancelled {
            do { try await clock.sleep(for: .seconds(1)) } catch { break }
            continuation.yield(())
          }
          continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    })
  }

  /// Finished stream: a consuming `for await` exits at once, so tests don't hang
  /// on a never-ending poll.
  static var testValue: WorktreeFileChangeClient {
    Self(ticks: { _ in AsyncStream { $0.finish() } })
  }

  static var previewValue: WorktreeFileChangeClient {
    Self(ticks: { _ in AsyncStream { $0.finish() } })
  }
}
