import Foundation

/// Keeps the last good snapshot per provider so Pip can show stale-but-labelled
/// numbers right after launch instead of an empty popover.
public struct SnapshotCache: Sendable {
    let key: String
    let suiteName: String?

    public init(key: String = "pip.snapshotCache.v1", suiteName: String? = nil) {
        self.key = key
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    public func load() -> [ProviderID: ProviderSnapshot] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([ProviderSnapshot].self, from: data) else { return [:] }
        return Dictionary(list.map { ($0.provider, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public func save(_ snapshots: [ProviderID: ProviderSnapshot]) {
        guard let data = try? JSONEncoder().encode(Array(snapshots.values)) else { return }
        defaults.set(data, forKey: key)
    }
}
