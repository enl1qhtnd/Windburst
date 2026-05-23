import Foundation
import Combine
import WindburstShared

@MainActor
final class FanPreferencesStore: ObservableObject {
    static let shared = FanPreferencesStore()

    private let url: URL
    @Published private(set) var collection: FanPreferencesCollection

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("Windburst", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("fan-preferences.json")
        collection = Self.load(from: url) ?? FanPreferencesCollection()
    }

    func preferences(for index: Int) -> FanIndividualPreferences {
        collection.preferences(for: index)
    }

    func isHidden(_ index: Int) -> Bool {
        preferences(for: index).isHidden
    }

    func update(for index: Int, transform: (inout FanIndividualPreferences) -> Void) {
        var preferences = collection.preferences(for: index)
        transform(&preferences)
        collection.setPreferences(preferences)
        save()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(collection) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func load(from url: URL) -> FanPreferencesCollection? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FanPreferencesCollection.self, from: data)
    }
}
