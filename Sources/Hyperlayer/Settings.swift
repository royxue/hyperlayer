import Combine
import Foundation

/// User preferences, persisted in UserDefaults. Shared by the menu, the key mapping
/// overlay and the event tap, so a change in one place applies everywhere at once.
final class Settings: ObservableObject {
    private enum Keys {
        static let layerEnabled = "layerEnabled"
        static let tapForEscape = "tapForEscape"
    }

    private let defaults: UserDefaults

    /// Apply `NavigationLayer` mappings while hyper is held.
    @Published var layerEnabled: Bool {
        didSet { defaults.set(layerEnabled, forKey: Keys.layerEnabled) }
    }

    /// Send Escape when Caps Lock is pressed and released without another key.
    @Published var tapForEscape: Bool {
        didSet { defaults.set(tapForEscape, forKey: Keys.tapForEscape) }
    }

    /// Optional layer keys that are turned on.
    @Published var layerOptions: Set<LayerOption> {
        didSet {
            for option in LayerOption.allCases {
                defaults.set(layerOptions.contains(option), forKey: option.defaultsKey)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var registered: [String: Any] = [Keys.layerEnabled: true, Keys.tapForEscape: false]
        for option in LayerOption.allCases {
            registered[option.defaultsKey] = option.isOnByDefault
        }
        defaults.register(defaults: registered)

        layerEnabled = defaults.bool(forKey: Keys.layerEnabled)
        tapForEscape = defaults.bool(forKey: Keys.tapForEscape)
        layerOptions = Set(LayerOption.allCases.filter { defaults.bool(forKey: $0.defaultsKey) })
    }

    func isOn(_ option: LayerOption) -> Bool {
        layerOptions.contains(option)
    }

    func set(_ option: LayerOption, on: Bool) {
        if on { layerOptions.insert(option) } else { layerOptions.remove(option) }
    }
}
