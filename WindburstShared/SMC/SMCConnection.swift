import Foundation
import IOKit

/// Apple SMC IO struct — must be exactly 80 bytes with SMCKit-compatible field layout.
struct SMCParamStruct {
    struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    enum Selector: UInt8 {
        case handleYPCEvent = 2
        case readKey = 5
        case writeKey = 6
        case getKeyFromIndex = 8
        case getKeyInfo = 9
    }

    enum Result: UInt8 {
        case success = 0
        case error = 1
        case keyNotFound = 132
    }

    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )

    var payload: Data {
        withUnsafeBytes(of: bytes) { Data($0) }
    }

    mutating func setPayload(_ data: Data) {
        data.prefix(32).withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            withUnsafeMutableBytes(of: &bytes) { buffer in
                memcpy(buffer.baseAddress, base, min(data.count, 32))
            }
        }
    }
}

private enum SMCStructLayout {
    static let size = MemoryLayout<SMCParamStruct>.stride

    static func assertValid() {
        assert(size == 80, "SMCParamStruct must be 80 bytes, got \(size)")
        assert(MemoryLayout<SMCParamStruct>.offset(of: \SMCParamStruct.data8) == 42)
    }
}

/// Low-level IOKit bridge to AppleSMC / VirtualSMC.
public final class SMCConnection: @unchecked Sendable {
    public static let kernelIndexSMC: UInt32 = 2

    private var connection: io_connect_t = 0
    private let lock = NSLock()

    public init() {
        SMCStructLayout.assertValid()
    }

    deinit {
        close()
    }

    public var isOpen: Bool {
        connection != 0
    }

    @discardableResult
    public func open() -> kern_return_t {
        lock.lock()
        defer { lock.unlock() }

        if connection != 0 { return KERN_SUCCESS }

        for serviceName in ["AppleSMC", "VirtualSMC"] {
            let matching = IOServiceMatching(serviceName)
            var iterator: io_iterator_t = 0
            let matchResult = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
            guard matchResult == KERN_SUCCESS else { continue }

            defer { IOObjectRelease(iterator) }

            let device = IOIteratorNext(iterator)
            guard device != 0 else { continue }

            defer { IOObjectRelease(device) }

            let openResult = IOServiceOpen(device, mach_task_self_, 0, &connection)
            if openResult == KERN_SUCCESS {
                return KERN_SUCCESS
            }
        }

        return KERN_FAILURE
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }

        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    public func readKey(_ key: String) throws -> (data: Data, type: UInt32) {
        var input = SMCParamStruct()
        input.key = Self.fourCharCode(from: key)
        input.data8 = SMCParamStruct.Selector.getKeyInfo.rawValue

        var output = try call(input: &input)

        let dataSize = output.keyInfo.dataSize
        let dataType = output.keyInfo.dataType

        input.keyInfo.dataSize = dataSize
        input.data8 = SMCParamStruct.Selector.readKey.rawValue

        output = try call(input: &input)

        guard output.result == SMCParamStruct.Result.success.rawValue else {
            throw SMCError.readFailed(key)
        }

        let size = min(Int(dataSize), 32)
        return (output.payload.prefix(size), dataType)
    }

    public func writeKey(_ key: String, data: Data) throws {
        var input = SMCParamStruct()
        input.key = Self.fourCharCode(from: key)
        input.data8 = SMCParamStruct.Selector.getKeyInfo.rawValue

        var output = try call(input: &input)

        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = SMCParamStruct.Selector.writeKey.rawValue
        input.setPayload(data)

        output = try call(input: &input)

        guard output.result == SMCParamStruct.Result.success.rawValue else {
            throw SMCError.writeFailed(key)
        }
    }

    public func keyAtIndex(_ index: UInt32) throws -> String? {
        var input = SMCParamStruct()
        input.data8 = SMCParamStruct.Selector.getKeyFromIndex.rawValue
        input.data32 = index

        do {
            let output = try call(input: &input)
            let key = Self.string(fromFourCharCode: output.key)
            guard key.count == 4, key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "#" || $0 == " ") }) else {
                return nil
            }
            return key
        } catch {
            return nil
        }
    }

    public func publicKeyCount() throws -> Int? {
        let (data, _) = try readKey("#KEY")
        guard data.count >= 4 else { return nil }
        let be = UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3])
        let le = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        let count = max(Int(be), Int(le))
        return count > 0 ? count : nil
    }

    public func enumerateKeys() throws -> [String] {
        var keys: [String] = []
        let expectedCount = try? publicKeyCount()

        var index: UInt32 = 0
        while true {
            if let expectedCount, Int(index) >= expectedCount { break }
            guard let key = try keyAtIndex(index) else { break }
            keys.append(key)
            index += 1
            if index > 2048 { break }
        }

        return keys
    }

    public struct DumpDiagnostics {
        public let values: [String: String]
        public let keyCount: Int
        public let sampleError: String?
    }

    public func dumpAllKeys() throws -> DumpDiagnostics {
        var values: [String: String] = [:]
        var sampleError: String?

        let keys = (try? enumerateKeys()) ?? []
        for key in keys {
            do {
                let typed = try readKey(key)
                let hex = typed.data.map { String(format: "%02X", $0) }.joined(separator: " ")
                let type = Self.string(fromFourCharType: typed.type)
                values[key] = "\(hex) [\(type)]"
            } catch {
                sampleError = sampleError ?? "\(key): \(error.localizedDescription)"
            }
        }

        if values.isEmpty {
            for key in SMCKeyCatalog.probeTemperatureKeys + (0..<8).map { SMCKeyCatalog.fanActualKey(index: $0) } + ["#KEY", "FNum"] {
                do {
                    let typed = try readKey(key)
                    let hex = typed.data.map { String(format: "%02X", $0) }.joined(separator: " ")
                    let type = Self.string(fromFourCharType: typed.type)
                    values[key] = "\(hex) [\(type)]"
                } catch {
                    sampleError = sampleError ?? "\(key): \(error.localizedDescription)"
                }
            }
        }

        return DumpDiagnostics(values: values, keyCount: keys.count, sampleError: sampleError)
    }

    @discardableResult
    private func call(input: inout SMCParamStruct) throws -> SMCParamStruct {
        guard connection != 0 else {
            throw SMCError.notConnected
        }

        var output = SMCParamStruct()
        var outputSize = SMCStructLayout.size

        let ioResult = withUnsafeMutablePointer(to: &input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                IOConnectCallStructMethod(
                    connection,
                    Self.kernelIndexSMC,
                    inputPointer,
                    SMCStructLayout.size,
                    outputPointer,
                    &outputSize
                )
            }
        }

        switch (ioResult, output.result) {
        case (KERN_SUCCESS, SMCParamStruct.Result.success.rawValue):
            return output
        case (KERN_SUCCESS, SMCParamStruct.Result.keyNotFound.rawValue):
            throw SMCError.keyNotFound(Self.string(fromFourCharCode: input.key))
        case (KERN_SUCCESS, _):
            return output
        default:
            throw SMCError.ioKitError(ioResult)
        }
    }

    public static func fourCharCode(from string: String) -> UInt32 {
        string.utf8.reduce(0) { sum, character in
            (sum << 8) | UInt32(character)
        }
    }

    public static func string(fromFourCharCode code: UInt32) -> String {
        let chars = [
            UnicodeScalar((code >> 24) & 0xFF),
            UnicodeScalar((code >> 16) & 0xFF),
            UnicodeScalar((code >> 8) & 0xFF),
            UnicodeScalar(code & 0xFF)
        ].compactMap { $0 }
        return String(String.UnicodeScalarView(chars))
    }

    public static func string(fromFourCharType code: UInt32) -> String {
        string(fromFourCharCode: code)
    }
}

public enum SMCError: Error, LocalizedError {
    case notConnected
    case keyNotFound(String)
    case readFailed(String)
    case writeFailed(String)
    case ioKitError(kern_return_t)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "SMC connection is not open"
        case .keyNotFound(let key):
            return "SMC key not found: \(key)"
        case .readFailed(let key):
            return "Failed to read SMC key: \(key)"
        case .writeFailed(let key):
            return "Failed to write SMC key: \(key)"
        case .ioKitError(let code):
            return "IOKit error: \(code)"
        case .parseFailed(let key):
            return "Failed to parse SMC value for key: \(key)"
        }
    }
}
