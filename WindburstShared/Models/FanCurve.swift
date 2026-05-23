import Foundation

public struct CurvePoint: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var temperature: Double
    public var fanPercent: Double

    public init(id: UUID = UUID(), temperature: Double, fanPercent: Double) {
        self.id = id
        self.temperature = temperature
        self.fanPercent = fanPercent
    }
}

public struct FanCurve: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var points: [CurvePoint]
    public var hysteresisCelsius: Double
    public var sensorKey: String?

    public init(
        id: UUID = UUID(),
        name: String,
        points: [CurvePoint],
        hysteresisCelsius: Double = 2.0,
        sensorKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.points = points.sorted { $0.temperature < $1.temperature }
        self.hysteresisCelsius = hysteresisCelsius
        self.sensorKey = sensorKey
    }

    public static func defaultCurve(name: String = "Balanced") -> FanCurve {
        FanCurve(
            name: name,
            points: [
                CurvePoint(temperature: 30, fanPercent: 20),
                CurvePoint(temperature: 50, fanPercent: 40),
                CurvePoint(temperature: 70, fanPercent: 70),
                CurvePoint(temperature: 85, fanPercent: 100)
            ]
        )
    }

    public static let silent = FanCurve(
        name: "Silent",
        points: [
            CurvePoint(temperature: 35, fanPercent: 15),
            CurvePoint(temperature: 55, fanPercent: 30),
            CurvePoint(temperature: 75, fanPercent: 55),
            CurvePoint(temperature: 90, fanPercent: 80)
        ]
    )

    public static let balanced = FanCurve.defaultCurve()

    public static let performance = FanCurve(
        name: "Performance",
        points: [
            CurvePoint(temperature: 25, fanPercent: 35),
            CurvePoint(temperature: 45, fanPercent: 55),
            CurvePoint(temperature: 60, fanPercent: 80),
            CurvePoint(temperature: 75, fanPercent: 100)
        ]
    )
}

public struct CurveAssignment: Codable, Sendable, Hashable {
    public var fanIndex: Int
    public var curveID: UUID
    public var sensorKey: String
    public var enabled: Bool

    public init(fanIndex: Int, curveID: UUID, sensorKey: String, enabled: Bool = true) {
        self.fanIndex = fanIndex
        self.curveID = curveID
        self.sensorKey = sensorKey
        self.enabled = enabled
    }
}

public struct CurveConfiguration: Codable, Sendable {
    public var curve: FanCurve
    public var fanIndices: [Int]
    public var sensorKey: String
    public var fanMinRPM: [Int: Int]
    public var fanMaxRPM: [Int: Int]
    public var minimumHoldSeconds: Double

    public init(
        curve: FanCurve,
        fanIndices: [Int],
        sensorKey: String,
        fanMinRPM: [Int: Int] = [:],
        fanMaxRPM: [Int: Int] = [:],
        minimumHoldSeconds: Double = 3.0
    ) {
        self.curve = curve
        self.fanIndices = fanIndices
        self.sensorKey = sensorKey
        self.fanMinRPM = fanMinRPM
        self.fanMaxRPM = fanMaxRPM
        self.minimumHoldSeconds = minimumHoldSeconds
    }

    enum CodingKeys: String, CodingKey {
        case curve, fanIndices, sensorKey, fanMinRPM, fanMaxRPM, minimumHoldSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        curve = try container.decode(FanCurve.self, forKey: .curve)
        fanIndices = try container.decode([Int].self, forKey: .fanIndices)
        sensorKey = try container.decode(String.self, forKey: .sensorKey)
        minimumHoldSeconds = try container.decode(Double.self, forKey: .minimumHoldSeconds)
        fanMinRPM = try Self.decodeIntMap(container, key: .fanMinRPM)
        fanMaxRPM = try Self.decodeIntMap(container, key: .fanMaxRPM)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(curve, forKey: .curve)
        try container.encode(fanIndices, forKey: .fanIndices)
        try container.encode(sensorKey, forKey: .sensorKey)
        try container.encode(minimumHoldSeconds, forKey: .minimumHoldSeconds)
        try Self.encodeIntMap(&container, key: .fanMinRPM, value: fanMinRPM)
        try Self.encodeIntMap(&container, key: .fanMaxRPM, value: fanMaxRPM)
    }

    private static func decodeIntMap(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> [Int: Int] {
        let stringKeyed = try container.decode([String: Int].self, forKey: key)
        return Dictionary(uniqueKeysWithValues: stringKeyed.compactMap { key, value in
            guard let intKey = Int(key) else { return nil }
            return (intKey, value)
        })
    }

    private static func encodeIntMap(_ container: inout KeyedEncodingContainer<CodingKeys>, key: CodingKeys, value: [Int: Int]) throws {
        let stringKeyed = Dictionary(uniqueKeysWithValues: value.map { (String($0.key), $0.value) })
        try container.encode(stringKeyed, forKey: key)
    }
}
