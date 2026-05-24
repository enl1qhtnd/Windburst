import Foundation
import Combine
import WindburstShared

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let url: URL
    @Published private(set) var settings: AppSettings

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("Windburst", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("settings.json")
        settings = Self.load(from: url) ?? .default
    }

    func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func update(_ transform: (inout AppSettings) -> Void) {
        transform(&settings)
        save()
    }

    private static func load(from url: URL) -> AppSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}

@MainActor
final class PresetStore: ObservableObject {
    static let shared = PresetStore()

    private let url: URL
    @Published var presets: [FanPreset]

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("Windburst", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("presets.json")
        presets = Self.load(from: url) ?? FanPreset.builtInPresets
    }

    func save() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func preset(named name: String) -> FanPreset? {
        presets.first { $0.name == name }
    }

    func preset(id: UUID) -> FanPreset? {
        presets.first { $0.id == id }
    }

    func upsert(_ preset: FanPreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        save()
    }

    func createPreset(name: String, curve: FanCurve) -> FanPreset {
        let preset = FanPreset(name: name, curve: curve)
        upsert(preset)
        return preset
    }

    func deletePreset(id: UUID) {
        guard let preset = preset(id: id), !preset.isBuiltIn else { return }
        presets.removeAll { $0.id == id }
        save()
    }

    func exportDocument() -> PresetExportDocument {
        PresetExportDocument(presets: presets.filter { !$0.isBuiltIn })
    }

    func importDocument(_ document: PresetExportDocument) {
        for preset in document.presets where !preset.isBuiltIn {
            upsert(preset)
        }
    }

    private static func load(from url: URL) -> [FanPreset]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let saved = (try? JSONDecoder().decode([FanPreset].self, from: data)) ?? []
        return mergePresets(saved)
    }

    private static func mergePresets(_ saved: [FanPreset]) -> [FanPreset] {
        var byID = Dictionary(uniqueKeysWithValues: FanPreset.builtInPresets.map { ($0.id, $0) })
        for preset in saved {
            if preset.id == FanPreset.burstID, var canonical = byID[preset.id] {
                canonical.linkedFanIndices = preset.linkedFanIndices
                byID[preset.id] = canonical
            } else {
                byID[preset.id] = preset
            }
        }
        let builtIn = FanPreset.builtInPresets.map { byID[$0.id] ?? $0 }
        let custom = saved.filter { savedPreset in
            !FanPreset.builtInPresets.contains { $0.id == savedPreset.id }
        }
        return builtIn + custom
    }
}
