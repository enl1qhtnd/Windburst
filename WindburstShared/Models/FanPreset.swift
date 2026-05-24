import Foundation

public struct FanPreset: Identifiable, Codable, Sendable, Hashable {
    public static let silentID = UUID(uuidString: "A0000001-0000-4000-8000-000000000001")!
    public static let balancedID = UUID(uuidString: "A0000002-0000-4000-8000-000000000002")!
    public static let performanceID = UUID(uuidString: "A0000003-0000-4000-8000-000000000003")!
    public static let burstID = UUID(uuidString: "A0000004-0000-4000-8000-000000000004")!

    public var id: UUID
    public var name: String
    public var curve: FanCurve
    public var linkedFanIndices: [Int]
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        curve: FanCurve,
        linkedFanIndices: [Int] = [],
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.curve = curve
        self.linkedFanIndices = linkedFanIndices
        self.isBuiltIn = isBuiltIn
    }

    public static let builtInPresets: [FanPreset] = [
        FanPreset(id: silentID, name: "Silent", curve: .silent, isBuiltIn: true),
        FanPreset(id: balancedID, name: "Balanced", curve: .balanced, isBuiltIn: true),
        FanPreset(id: performanceID, name: "Performance", curve: .performance, isBuiltIn: true),
        FanPreset(id: burstID, name: "Burst", curve: .burst, isBuiltIn: true)
    ]

    public static var defaultCurveID: UUID { balancedID }
}

public struct PresetExportDocument: Codable, Sendable {
    public var version: Int
    public var exportedAt: Date
    public var presets: [FanPreset]

    public init(version: Int = 1, exportedAt: Date = Date(), presets: [FanPreset]) {
        self.version = version
        self.exportedAt = exportedAt
        self.presets = presets
    }
}
