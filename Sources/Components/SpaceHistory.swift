import Foundation

/// History of recently-activated Spaces backing the ^⇧← hotkey.
///
/// Model:
/// - Every real Space change records the Space we left, so ^⇧← ("back to
///   the previously-active Space") returns to the Space that was active
///   just before, and can be pressed repeatedly to walk further back
///   through the history array.
/// - There is deliberately no forward counterpart: desktops never move,
///   and a forward key paired with the system's own Ctrl+← / Ctrl+→
///   navigation would only invite misalignment — "previous Space" is a
///   single, deterministic direction.
///
/// Must only be called from the main thread — the monitor's Combine sink
/// and the hotkey handler both run there.
final class SpaceHistory {
    /// Longest back history kept; older entries are dropped off the front.
    static let maxBackEntries = 32

    /// Spaces we can jump back into, most recent last.
    private(set) var back: [UInt64] = []
    /// The Space currently active; nil until the first observed arrival.
    private(set) var currentSpaceID: UInt64?

    private let maxBackEntries: Int

    /// Spaces in-flight ^⇧← jumps are heading for; the next arrival
    /// matching one counts as our own switch, so it is not re-recorded
    /// into `back` and the walk-steps stay stable. A Set rather than a
    /// single slot because two ← presses inside one switch animation
    /// produce two overlapping arrivals. A posted key that never produces
    /// a change leaves a stale entry, which merely consumes the next
    /// matching arrival — no worse than a single pending target.
    private var pendingTargets: Set<UInt64> = []

    /// Performs the actual Space switch. Returns false when the jump could
    /// not be posted (missing permission, target gone, shortcut disabled…)
    /// — the history is left untouched in that case.
    private let jump: (UInt64) -> Bool

    /// - Parameters:
    ///   - maxBackEntries: back-history cap (injectable for tests).
    ///   - jump: posts the switch to the given Space; never called when
    ///     there is nothing to go back into.
    init(
        maxBackEntries: Int = SpaceHistory.maxBackEntries,
        jump: @escaping (UInt64) -> Bool
    ) {
        self.maxBackEntries = maxBackEntries
        self.jump = jump
    }

    /// Feeds an observed Space change (our own jumps included). Space ID 0
    /// — the private API being unavailable — is ignored so it never
    /// pollutes the history.
    func recordArrival(_ id: UInt64) {
        guard id != 0 else { return }
        guard id != currentSpaceID else { return }
        let internalSwitch = pendingTargets.remove(id) != nil
        if let previous = currentSpaceID, !internalSwitch {
            back.append(previous)
            if back.count > maxBackEntries {
                back.removeFirst(back.count - maxBackEntries)
            }
        }
        currentSpaceID = id
    }

    /// ^⇧←: switch to the Space that was active just before; repeated
    /// presses walk further back. Returns false when there is no history
    /// to go back to or the jump could not be posted.
    @discardableResult
    func goBack() -> Bool {
        guard let target = back.last else { return false }
        guard jump(target) else { return false }
        back.removeLast()
        pendingTargets.insert(target)
        return true
    }
}
