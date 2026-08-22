import Combine
import Foundation

struct SpaceLabel: Codable, Equatable {
    var name: String
    var colorHex: String
}

/// Persists per-Space labels to UserDefaults.
/// New Spaces auto-assign a default name ("Space N") and a color from a rotating palette.
final class SpaceStore: ObservableObject {
    @Published var labels: [UInt64: SpaceLabel] = [:]
    /// True while a name is being edited in the popover. The menu bar label
    /// stays frozen (no width jitter from the partially-typed name) until
    /// the edit session ends (⏎/Esc/click-away).
    @Published var isRenaming = false

    private let labelsKey = "SpaceLabels.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func label(for id: UInt64) -> SpaceLabel {
        if let existing = labels[id] { return existing }
        return autoAssign(id)
    }

    func update(_ id: UInt64, _ label: SpaceLabel) {
        labels[id] = label
        save()
    }

    func remove(_ id: UInt64) {
        labels.removeValue(forKey: id)
        save()
    }

    @discardableResult
    private func autoAssign(_ id: UInt64) -> SpaceLabel {
        let n = labels.count + 1
        let color = SpacePalette.colors[n % SpacePalette.colors.count]
        let label = SpaceLabel(name: "Space \(n)", colorHex: color)
        labels[id] = label
        save()
        return label
    }

    private func load() {
        if let data = defaults.data(forKey: labelsKey),
            let decoded = try? JSONDecoder().decode([String: SpaceLabel].self, from: data)
        {
            var converted: [UInt64: SpaceLabel] = [:]
            for (key, value) in decoded {
                if let id = UInt64(key) {
                    converted[id] = value
                }
            }
            labels = converted
        }
    }

    private func save() {
        var stringKeyed: [String: SpaceLabel] = [:]
        for (key, value) in labels {
            stringKeyed[String(key)] = value
        }
        if let data = try? JSONEncoder().encode(stringKeyed) {
            defaults.set(data, forKey: labelsKey)
        }
    }
}
