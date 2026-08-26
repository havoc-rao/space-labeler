import Foundation

/// Pure matching logic for the popover's Space-list filter field. Kept
/// separate from the view so the behavior is unit-testable.
enum SpaceFilter {
    /// Whether a Space row (label name + live desktop number) matches the
    /// typed query, as a case-insensitive substring of either. A blank
    /// query matches everything.
    static func matches(name: String, desktop: Int, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if name.localizedCaseInsensitiveContains(q) { return true }
        if desktop > 0, String(desktop).localizedCaseInsensitiveContains(q) { return true }
        return false
    }
}
