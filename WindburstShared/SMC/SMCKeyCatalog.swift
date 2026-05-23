import Foundation

/// Known SMC keys for Intel Macs and VirtualSMC Hackintosh setups.
public enum SMCKeyCatalog {
    public static let preferredTemperatureKeys: [String] = [
        "TC0D", "TC0P", "TCXC", "TC0E", "TC0F", "TC0H", "TC0J",
        "TC1C", "TC2C", "TC3C", "TC4C", "TC5C", "TC6C", "TC7C",
        "TCAD", "TCAH", "TCAC", "TCGC", "TCFC",
        "TG0P", "TG0D", "TG0H", "TG0F",
        "Tm0P", "TN0P", "TW0P", "TA0P", "Tp0P",
        "PCPR", "PCPT", "PCPC", "PCPL",
        "TH0A", "TH0B", "TH0C", "TH0F",
        "TsHS", "TMBS"
    ]

    private static let excludedTemperatureKeys: Set<String> = [
        "Th0H", "Th1H", "Th2H", "CLKT", "CLKH"
    ]

    public static func isLikelyTemperatureKey(_ key: String) -> Bool {
        guard key.count == 4, key.allSatisfy(\.isASCII) else { return false }
        guard !excludedTemperatureKeys.contains(key) else { return false }

        let first = key.first ?? " "
        guard first == "T" || first == "P" else { return false }
        if key.hasPrefix("F") { return false }

        if preferredTemperatureKeys.contains(key) { return true }
        if key.hasPrefix("TC") || key.hasPrefix("TG") || key.hasPrefix("TH") { return true }
        if key.hasPrefix("PC") { return true }
        if key.hasPrefix("Tm") || key.hasPrefix("TN") || key.hasPrefix("TW") || key.hasPrefix("TA") { return true }
        if key.hasPrefix("Tp") { return true }

        // VirtualSMC / SuperIO may expose other Txxx keys — accept readable 4-char T* keys.
        if first == "T" {
            let suffix = key.dropFirst()
            return suffix.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " }
        }

        return false
    }

    public static func fanActualKey(index: Int) -> String {
        "F\(index)Ac"
    }

    public static func fanMinKey(index: Int) -> String {
        "F\(index)Mn"
    }

    public static func fanMaxKey(index: Int) -> String {
        "F\(index)Mx"
    }

    public static func fanModeKey(index: Int) -> String {
        "F\(index)Md"
    }

    public static func fanTargetKey(index: Int) -> String {
        "F\(index)Tg"
    }

    public static func fanIDKey(index: Int) -> String {
        "F\(index)ID"
    }

    public static func discoverFanIndices(from keys: [String]) -> [Int] {
        var indices = Set<Int>()
        for key in keys where key.count == 4 {
            guard key.first == "F" else { continue }
            let suffix = key.dropFirst()
            if suffix.hasSuffix("Ac") || suffix.hasSuffix("Mn") || suffix.hasSuffix("Mx") || suffix.hasSuffix("Md") {
                let middle = suffix.dropLast(2)
                if let index = Int(middle) {
                    indices.insert(index)
                }
            }
        }
        return indices.sorted()
    }

    public static func temperaturePriority(for key: String) -> Int {
        if let index = preferredTemperatureKeys.firstIndex(of: key) {
            return index
        }
        if key.hasPrefix("TC") { return 100 }
        if key.hasPrefix("TG") { return 110 }
        if key.hasPrefix("TH") { return 120 }
        if key.hasPrefix("PC") { return 130 }
        if key.hasPrefix("T") { return 200 }
        return 999
    }

    public static func defaultPrimarySensor(from sensors: [Sensor]) -> Sensor? {
        sensors
            .filter { $0.isAvailable }
            .sorted { lhs, rhs in
                let lp = temperaturePriority(for: lhs.key)
                let rp = temperaturePriority(for: rhs.key)
                if lp != rp { return lp < rp }
                return lhs.key < rhs.key
            }
            .first
    }

    /// Keys to probe directly when enumeration is incomplete (common on Hackintosh).
    public static var probeTemperatureKeys: [String] {
        preferredTemperatureKeys + (0..<8).flatMap { index in
            ["TC\(index)C", "TC\(index)D", "TC\(index)P", "TC\(index)E"]
        }
    }
}
