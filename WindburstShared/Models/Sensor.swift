import Foundation

public struct Sensor: Identifiable, Codable, Sendable, Hashable {
    public var id: String { key }
    public let key: String
    public var name: String
    public var temperature: Double?
    public var isAvailable: Bool

    public init(key: String, name: String, temperature: Double?, isAvailable: Bool) {
        self.key = key
        self.name = name
        self.temperature = temperature
        self.isAvailable = isAvailable
    }
}
