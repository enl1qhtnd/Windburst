import Foundation

public enum SMCValueParser {
    public static func parseTemperature(data: Data, type: UInt32? = nil, key: String) throws -> Double {
        guard !data.isEmpty else { throw SMCError.parseFailed(key) }

        if let type {
            if let value = parseByType(data: data, type: type, key: key, asTemperature: true) {
                return value
            }
        }

        // sp78: signed 7.8 fixed point (VirtualSMC / Intel default for T* keys)
        if data.count >= 2 {
            let sp78 = Double(Int8(bitPattern: data[0])) + Double(data[1]) / 256.0
            if sp78 > -40 && sp78 < 150 {
                return sp78
            }
        }

        // fpe2
        if data.count >= 2 {
            let fpe2 = (Double(UInt16(data[0]) << 8 | UInt16(data[1])) / 16384.0) * 4.0
            if fpe2 > -40 && fpe2 < 150 {
                return fpe2
            }
        }

        // flt
        if data.count >= 4 {
            let value = data.withUnsafeBytes { $0.load(as: Float.self) }
            let temp = Double(value)
            if temp > -40 && temp < 150 {
                return temp
            }
        }

        if data.count == 1 {
            let value = Double(data[0])
            if value > 0 && value < 150 { return value }
        }

        if data.count >= 2 {
            let ui16 = Double(UInt16(data[0]) << 8 | UInt16(data[1]))
            if ui16 > 0 && ui16 < 150 {
                return ui16
            }
        }

        throw SMCError.parseFailed(key)
    }

    public static func parseRPM(data: Data, type: UInt32? = nil, key: String) throws -> Int {
        guard data.count >= 2 else { throw SMCError.parseFailed(key) }

        if let type, let value = parseByType(data: data, type: type, key: key, asTemperature: false) {
            return Int(value.rounded())
        }

        let raw = UInt16(data[0]) << 8 | UInt16(data[1])

        // VirtualSMC / AppleSMC fan keys use integer fpe2 (decodeIntFp), not floating fpe2.
        let intFp = Int(raw >> 2)
        if intFp > 0 {
            return intFp
        }

        let ui16 = Int(raw)
        if ui16 > 0 {
            return ui16
        }

        throw SMCError.parseFailed(key)
    }

    public static func parseUInt8(data: Data) -> Int {
        Int(data.first ?? 0)
    }

    public static func encodeRPM(_ rpm: Int) -> Data {
        encodeIntFpFpe2(min(max(rpm, 0), 16383))
    }

    public static func encodeUInt8(_ value: Int) -> Data {
        Data([UInt8(min(max(value, 0), 255))])
    }

    private static func parseByType(data: Data, type: UInt32, key: String, asTemperature: Bool) -> Double? {
        let typeString = SMCConnection.string(fromFourCharType: type)

        switch typeString {
        case "sp78", "sp87", "sp96":
            guard data.count >= 2 else { return nil }
            let value = Double(Int8(bitPattern: data[0])) + Double(data[1]) / 256.0
            return asTemperature && value > -40 && value < 150 ? value : nil
        case "fpe2":
            guard data.count >= 2 else { return nil }
            let raw = UInt16(data[0]) << 8 | UInt16(data[1])
            if asTemperature {
                let value = Double(raw) / 4.0
                return value > -40 && value < 150 ? value : nil
            }
            let value = Double(raw >> 2)
            return value > 0 ? value : nil
        case "flt ", "float":
            guard data.count >= 4 else { return nil }
            let value = Double(data.withUnsafeBytes { $0.load(as: Float.self) })
            if asTemperature {
                return value > -40 && value < 150 ? value : nil
            }
            return value > 0 ? value : nil
        case "ui16":
            guard data.count >= 2 else { return nil }
            let value = Double(UInt16(data[0]) << 8 | UInt16(data[1]))
            if asTemperature {
                return value > 0 && value < 150 ? value : nil
            }
            return value > 0 ? value : nil
        case "ui8 ", "ui8":
            guard let byte = data.first else { return nil }
            let value = Double(byte)
            return asTemperature ? (value > 0 && value < 150 ? value : nil) : (value > 0 ? value : nil)
        default:
            return nil
        }
    }

    private static func encodeIntFpFpe2(_ value: Int) -> Data {
        let encoded = UInt16(value << 2)
        return Data([UInt8((encoded >> 8) & 0xFF), UInt8(encoded & 0xFF)])
    }
}
