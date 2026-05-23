import Foundation

public final class SMCDriver: @unchecked Sendable {
    private let connection = SMCConnection()
    private let lock = NSLock()

    public init() {}

    public var isConnected: Bool {
        connection.isOpen
    }

    @discardableResult
    public func open() throws -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let result = connection.open()
        guard result == KERN_SUCCESS else {
            throw SMCError.ioKitError(result)
        }
        return true
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        connection.close()
    }

    public func enumerateKeys() throws -> [String] {
        try connection.enumerateKeys()
    }

    public func readRaw(key: String) throws -> Data {
        try connection.readKey(key).data
    }

    public func readTyped(key: String) throws -> (data: Data, type: UInt32) {
        try connection.readKey(key)
    }

    public func dumpAllKeys() throws -> [String: String] {
        if !isConnected {
            try open()
        }
        let diagnostics = try connection.dumpAllKeys()
        if diagnostics.values.isEmpty {
            if let sampleError = diagnostics.sampleError {
                throw SMCError.readFailed("No readable keys (\(diagnostics.keyCount) indexed). Example: \(sampleError)")
            }
            throw SMCError.readFailed("No readable keys (\(diagnostics.keyCount) indexed)")
        }
        return diagnostics.values
    }

    public func writeRaw(key: String, data: Data) throws {
        try connection.writeKey(key, data: data)
    }

    public func readTemperature(key: String) throws -> Double {
        let typed = try readTyped(key: key)
        return try SMCValueParser.parseTemperature(data: typed.data, type: typed.type, key: key)
    }

    public func readRPM(key: String) throws -> Int {
        let typed = try readTyped(key: key)
        return try SMCValueParser.parseRPM(data: typed.data, type: typed.type, key: key)
    }

    public func readUInt8(key: String) throws -> Int {
        let data = try readRaw(key: key)
        return SMCValueParser.parseUInt8(data: data)
    }

    public func discoverSensors(from keys: [String]? = nil) throws -> [Sensor] {
        let enumerated = try keys ?? enumerateKeys()
        let candidateKeys = orderedUnique(SMCKeyCatalog.probeTemperatureKeys + enumerated)
        var sensorsByKey: [String: Sensor] = [:]

        for key in candidateKeys where SMCKeyCatalog.isLikelyTemperatureKey(key) {
            do {
                let temp = try readTemperature(key: key)
                if temp > -40 && temp < 150 {
                    sensorsByKey[key] = Sensor(
                        key: key,
                        name: SMCKeyCatalog.displayName(for: key),
                        temperature: temp,
                        isAvailable: true
                    )
                }
            } catch {
                continue
            }
        }

        return sensorsByKey.values.sorted { lhs, rhs in
            SMCKeyCatalog.temperaturePriority(for: lhs.key) < SMCKeyCatalog.temperaturePriority(for: rhs.key)
        }
    }

    public func discoverFans(from keys: [String]? = nil) throws -> [Fan] {
        let allKeys = try keys ?? enumerateKeys()
        let probeKeys = orderedUnique(allKeys + (0..<8).flatMap { index in
            [
                SMCKeyCatalog.fanActualKey(index: index),
                SMCKeyCatalog.fanMinKey(index: index),
                SMCKeyCatalog.fanMaxKey(index: index),
                SMCKeyCatalog.fanModeKey(index: index)
            ]
        })
        let indices = SMCKeyCatalog.discoverFanIndices(from: probeKeys)
        var fans: [Fan] = []

        for index in indices {
            let actualKey = SMCKeyCatalog.fanActualKey(index: index)

            let currentRPM = (try? readRPM(key: actualKey)) ?? 0
            let minRPM = (try? readRPM(key: SMCKeyCatalog.fanMinKey(index: index))) ?? 800
            let maxRPM = (try? readRPM(key: SMCKeyCatalog.fanMaxKey(index: index))) ?? 6000
            let modeValue = (try? readUInt8(key: SMCKeyCatalog.fanModeKey(index: index))) ?? 0
            let mode: FanMode = modeValue == 0 ? .automatic : .manual

            fans.append(Fan(
                index: index,
                name: "Fan \(index + 1)",
                currentRPM: currentRPM,
                minRPM: max(minRPM, 500),
                maxRPM: max(maxRPM, minRPM + 100),
                mode: mode,
                controlMode: .automatic
            ))
        }

        return fans
    }

    public func setFanManualMode(index: Int) throws {
        try writeRaw(key: SMCKeyCatalog.fanModeKey(index: index), data: SMCValueParser.encodeUInt8(1))
    }

    public func setFanAutoMode(index: Int) throws {
        try writeRaw(key: SMCKeyCatalog.fanModeKey(index: index), data: SMCValueParser.encodeUInt8(0))
    }

    public func setFanTargetRPM(index: Int, rpm: Int, minRPM: Int, maxRPM: Int) throws {
        let clamped = min(max(rpm, minRPM), maxRPM)
        try setFanManualMode(index: index)
        try writeRaw(
            key: SMCKeyCatalog.fanTargetKey(index: index),
            data: SMCValueParser.encodeRPM(clamped)
        )
    }

    public func restoreAllFansToAuto(fans: [Fan]) {
        for fan in fans {
            try? setFanAutoMode(index: fan.index)
        }
    }

    private func orderedUnique(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for key in keys where seen.insert(key).inserted {
            ordered.append(key)
        }
        return ordered
    }
}

extension SMCKeyCatalog {
    public static func displayName(for key: String) -> String {
        switch key {
        case "TC0D": return "CPU Die"
        case "TC0P": return "CPU Proximity"
        case "TCXC": return "CPU Core Max"
        case "TG0P": return "GPU Proximity"
        case "TG0D": return "GPU Die"
        case "Tm0P": return "Memory Proximity"
        case "TN0P": return "Northbridge Proximity"
        default:
            if key.hasSuffix("C"), key.hasPrefix("TC") {
                return "Core \(key.dropFirst(2).dropLast())"
            }
            return key
        }
    }
}
