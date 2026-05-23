import Foundation

public enum FanMode: String, Codable, Sendable, CaseIterable {
    case automatic = "Auto"
    case manual = "Manual"
}

public enum FanControlMode: String, Codable, Sendable, CaseIterable {
    case automatic = "Auto"
    case manual = "Manual"
    case curve = "Curve"
}

public struct Fan: Identifiable, Codable, Sendable, Hashable {
    public var id: Int { index }
    public let index: Int
    public var name: String
    public var currentRPM: Int
    public var minRPM: Int
    public var maxRPM: Int
    public var mode: FanMode
    public var controlMode: FanControlMode
    public var targetRPM: Int?
    public var assignedCurveID: UUID?
    public var userMinRPM: Int?
    public var userMaxRPM: Int?
    public var controlSource: FanControlSource
    public var liquidctl: LiquidctlIdentity?

    public init(
        index: Int,
        name: String,
        currentRPM: Int,
        minRPM: Int,
        maxRPM: Int,
        mode: FanMode,
        controlMode: FanControlMode = .automatic,
        targetRPM: Int? = nil,
        assignedCurveID: UUID? = nil,
        userMinRPM: Int? = nil,
        userMaxRPM: Int? = nil,
        controlSource: FanControlSource = .smc,
        liquidctl: LiquidctlIdentity? = nil
    ) {
        self.index = index
        self.name = name
        self.currentRPM = currentRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.mode = mode
        self.controlMode = controlMode
        self.targetRPM = targetRPM
        self.assignedCurveID = assignedCurveID
        self.userMinRPM = userMinRPM
        self.userMaxRPM = userMaxRPM
        self.controlSource = controlSource
        self.liquidctl = liquidctl
    }

    public var effectiveMinRPM: Int {
        userMinRPM ?? minRPM
    }

    public var effectiveMaxRPM: Int {
        userMaxRPM ?? maxRPM
    }

    public var rpmPercent: Double {
        let range = Double(effectiveMaxRPM - effectiveMinRPM)
        guard range > 0 else { return 0 }
        return min(max(Double(currentRPM - effectiveMinRPM) / range, 0), 1)
    }

    enum CodingKeys: String, CodingKey {
        case index, name, currentRPM, minRPM, maxRPM, mode, controlMode, targetRPM
        case assignedCurveID, userMinRPM, userMaxRPM, controlSource, liquidctl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)
        name = try container.decode(String.self, forKey: .name)
        currentRPM = try container.decode(Int.self, forKey: .currentRPM)
        minRPM = try container.decode(Int.self, forKey: .minRPM)
        maxRPM = try container.decode(Int.self, forKey: .maxRPM)
        mode = try container.decode(FanMode.self, forKey: .mode)
        controlMode = try container.decodeIfPresent(FanControlMode.self, forKey: .controlMode) ?? .automatic
        targetRPM = try container.decodeIfPresent(Int.self, forKey: .targetRPM)
        assignedCurveID = try container.decodeIfPresent(UUID.self, forKey: .assignedCurveID)
        userMinRPM = try container.decodeIfPresent(Int.self, forKey: .userMinRPM)
        userMaxRPM = try container.decodeIfPresent(Int.self, forKey: .userMaxRPM)
        controlSource = try container.decodeIfPresent(FanControlSource.self, forKey: .controlSource) ?? .smc
        liquidctl = try container.decodeIfPresent(LiquidctlIdentity.self, forKey: .liquidctl)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(name, forKey: .name)
        try container.encode(currentRPM, forKey: .currentRPM)
        try container.encode(minRPM, forKey: .minRPM)
        try container.encode(maxRPM, forKey: .maxRPM)
        try container.encode(mode, forKey: .mode)
        try container.encode(controlMode, forKey: .controlMode)
        try container.encodeIfPresent(targetRPM, forKey: .targetRPM)
        try container.encodeIfPresent(assignedCurveID, forKey: .assignedCurveID)
        try container.encodeIfPresent(userMinRPM, forKey: .userMinRPM)
        try container.encodeIfPresent(userMaxRPM, forKey: .userMaxRPM)
        try container.encode(controlSource, forKey: .controlSource)
        try container.encodeIfPresent(liquidctl, forKey: .liquidctl)
    }
}
