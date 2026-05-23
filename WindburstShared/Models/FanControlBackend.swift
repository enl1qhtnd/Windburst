import Foundation

public enum FanControlBackend: String, Codable, CaseIterable, Sendable {
    case smc = "SMC (VirtualSMC)"
    case liquidctl = "liquidctl"

    public var requiresHelper: Bool {
        self == .smc
    }
}

public enum FanControlSource: String, Codable, Sendable {
    case smc
    case liquidctl
}

public struct LiquidctlIdentity: Codable, Sendable, Hashable {
    public let deviceIndex: Int
    public let channel: String
    public let deviceDescription: String

    public init(deviceIndex: Int, channel: String, deviceDescription: String) {
        self.deviceIndex = deviceIndex
        self.channel = channel
        self.deviceDescription = deviceDescription
    }

    public static func fanIndex(deviceIndex: Int, channel: String) -> Int {
        let channelNumber = channelNumber(from: channel)
        return 10_000 + deviceIndex * 100 + channelNumber
    }

    public static func channelNumber(from channel: String) -> Int {
        guard channel.hasPrefix("fan") else { return 0 }
        return Int(channel.dropFirst(3)) ?? 0
    }

    public static func channelName(number: Int) -> String {
        "fan\(number)"
    }
}
