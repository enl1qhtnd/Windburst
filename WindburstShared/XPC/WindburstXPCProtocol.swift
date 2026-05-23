import Foundation

@objc public protocol WindburstHelperProtocol {
    func ping(reply: @escaping (Bool) -> Void)
    func discoverFans(reply: @escaping (Data) -> Void)
    func discoverSensors(reply: @escaping (Data) -> Void)
    func readAllKeys(reply: @escaping (Data) -> Void)
    func setManualMode(fanIndex: Int, reply: @escaping (Bool, String?) -> Void)
    func setAutoMode(fanIndex: Int, reply: @escaping (Bool, String?) -> Void)
    func setTargetRPM(fanIndex: Int, rpm: Int, reply: @escaping (Bool, String?) -> Void)
    func startCurve(_ configData: Data, reply: @escaping (Bool, String?) -> Void)
    func stopCurve(fanIndex: Int, reply: @escaping (Bool, String?) -> Void)
    func stopAllCurves(reply: @escaping (Bool) -> Void)
    func getActiveCurveStatus(reply: @escaping (Data) -> Void)
    func shutdown(reply: @escaping (Bool) -> Void)
}

@objc public protocol WindburstHelperClientProtocol {
    func helperDidUpdateTargetRPM(fanIndex: Int, rpm: Int)
    func helperDidEncounterError(_ message: String)
}

public enum WindburstXPCConstants {
    public static let machServiceName = "de.enl1qhtnd.windburst.helper"
    public static let helperBundleIdentifier = "de.enl1qhtnd.windburst.helper"
    public static let appBundleIdentifier = "de.enl1qhtnd.windburst"
    public static let helperLabel = "de.enl1qhtnd.windburst.helper"
}

public enum XPCCodec {
    public static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}

public struct HelperStatus: Sendable {
    public var isConnected: Bool
    public var isRegistered: Bool
    public var lastError: String?

    public init(isConnected: Bool = false, isRegistered: Bool = false, lastError: String? = nil) {
        self.isConnected = isConnected
        self.isRegistered = isRegistered
        self.lastError = lastError
    }
}

public struct ActiveCurveStatus: Codable, Sendable {
    public var targets: [Int: Int]

    public init(targets: [Int: Int] = [:]) {
        self.targets = targets
    }

    enum CodingKeys: String, CodingKey {
        case targets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stringKeyed = try container.decode([String: Int].self, forKey: .targets)
        targets = Dictionary(uniqueKeysWithValues: stringKeyed.compactMap { key, value in
            guard let intKey = Int(key) else { return nil }
            return (intKey, value)
        })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let stringKeyed = Dictionary(uniqueKeysWithValues: targets.map { (String($0.key), $0.value) })
        try container.encode(stringKeyed, forKey: .targets)
    }
}
