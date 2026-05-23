import Foundation
import WindburstShared

struct LiquidctlDeviceRecord: Decodable {
    let description: String
    let vendorId: Int?
    let productId: Int?
    let driver: String?

    enum CodingKeys: String, CodingKey {
        case description
        case vendorId = "vendor_id"
        case productId = "product_id"
        case driver
    }
}

struct LiquidctlStatusRecord: Decodable {
    let description: String
    let status: [LiquidctlStatusEntry]
}

struct LiquidctlStatusEntry: Decodable {
    let key: String
    let value: Double
    let unit: String?
}

enum LiquidctlError: LocalizedError {
    case notInstalled
    case commandFailed(String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "liquidctl was not found. Install it with Homebrew (brew install liquidctl) or set a custom path in Settings."
        case .commandFailed(let message):
            return message
        case .invalidOutput(let message):
            return message
        }
    }
}

@MainActor
final class LiquidctlClient: ObservableObject {
    static let shared = LiquidctlClient()

    static let defaultMinRPM = 0
    static let defaultMaxRPM = 2400

    @Published private(set) var isAvailable = false
    @Published private(set) var lastError: String?
    @Published private(set) var resolvedPath: String?

    private var customPath: String?

    private init() {}

    func updateConfiguration(customPath: String?) {
        self.customPath = customPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        refreshAvailability()
    }

    func refreshAvailability() {
        resolvedPath = Self.resolveExecutable(customPath: customPath)
        isAvailable = resolvedPath != nil
        if !isAvailable {
            lastError = LiquidctlError.notInstalled.errorDescription
        } else {
            lastError = nil
        }
    }

    func discoverFans() async -> [Fan] {
        guard let path = resolvedPath ?? Self.resolveExecutable(customPath: customPath) else {
            lastError = LiquidctlError.notInstalled.errorDescription
            isAvailable = false
            return []
        }

        resolvedPath = path
        isAvailable = true

        do {
            let devices = try await listDevices(executablePath: path)
            var fans: [Fan] = []

            for (deviceIndex, device) in devices.enumerated() {
                let statusRecords = try await deviceStatus(deviceIndex: deviceIndex, executablePath: path)
                guard let status = statusRecords.first else { continue }

                for entry in status.status {
                    guard let channel = Self.parseFanChannel(from: entry.key) else { continue }
                    let fanIndex = LiquidctlIdentity.fanIndex(deviceIndex: deviceIndex, channel: channel)
                    let displayName = "\(device.description) · \(entry.key.replacingOccurrences(of: " speed", with: ""))"

                    fans.append(
                        Fan(
                            index: fanIndex,
                            name: displayName,
                            currentRPM: Int(entry.value.rounded()),
                            minRPM: Self.defaultMinRPM,
                            maxRPM: Self.defaultMaxRPM,
                            mode: .manual,
                            controlMode: .automatic,
                            controlSource: .liquidctl,
                            liquidctl: LiquidctlIdentity(
                                deviceIndex: deviceIndex,
                                channel: channel,
                                deviceDescription: device.description
                            )
                        )
                    )
                }
            }

            fans.sort { $0.index < $1.index }
            lastError = fans.isEmpty ? "No liquidctl fan channels found." : nil
            return fans
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func setSpeedPercent(for fan: Fan, percent: Double) async throws {
        guard let identity = fan.liquidctl else {
            throw LiquidctlError.invalidOutput("Missing liquidctl identity for fan \(fan.index)")
        }
        guard let path = resolvedPath ?? Self.resolveExecutable(customPath: customPath) else {
            throw LiquidctlError.notInstalled
        }

        let clamped = min(max(percent, 0), 100)
        let rounded = Int(clamped.rounded())
        _ = try await run(
            executablePath: path,
            arguments: ["-n", String(identity.deviceIndex), "set", identity.channel, "speed", String(rounded)]
        )
    }

    func setSpeedPercent(for fan: Fan, rpm: Int) async throws {
        let range = fan.effectiveMaxRPM - fan.effectiveMinRPM
        guard range > 0 else {
            try await setSpeedPercent(for: fan, percent: 0)
            return
        }
        let percent = (Double(rpm - fan.effectiveMinRPM) / Double(range)) * 100.0
        try await setSpeedPercent(for: fan, percent: percent)
    }

    func reportError(_ message: String) {
        lastError = message
    }

    func initializeAll() async throws {
        guard let path = resolvedPath ?? Self.resolveExecutable(customPath: customPath) else {
            throw LiquidctlError.notInstalled
        }
        _ = try await run(executablePath: path, arguments: ["initialize", "all"])
    }

    nonisolated static func resolveExecutable(customPath: String?) -> String? {
        if let customPath, !customPath.isEmpty {
            return FileManager.default.isExecutableFile(atPath: customPath) ? customPath : nil
        }

        let candidates = [
            "/opt/homebrew/bin/liquidctl",
            "/usr/local/bin/liquidctl",
            "/usr/bin/liquidctl"
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return resolveFromPath()
    }

    private nonisolated static func resolveFromPath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["liquidctl"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !path.isEmpty,
                FileManager.default.isExecutableFile(atPath: path) else {
                return nil
            }
            return path
        } catch {
            return nil
        }
    }

    private func listDevices(executablePath: String) async throws -> [LiquidctlDeviceRecord] {
        let data = try await run(executablePath: executablePath, arguments: ["--json", "list"])
        let devices = try JSONDecoder().decode([LiquidctlDeviceRecord].self, from: data)
        return devices
    }

    private func deviceStatus(deviceIndex: Int, executablePath: String) async throws -> [LiquidctlStatusRecord] {
        let data = try await run(
            executablePath: executablePath,
            arguments: ["--json", "-n", String(deviceIndex), "status"]
        )
        return try JSONDecoder().decode([LiquidctlStatusRecord].self, from: data)
    }

    private nonisolated func run(executablePath: String, arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try Self.runSync(executablePath: executablePath, arguments: arguments)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated static func runSync(executablePath: String, arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw LiquidctlError.commandFailed("Failed to run liquidctl: \(error.localizedDescription)")
        }

        process.waitUntilExit()
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let message = errorText.isEmpty ? "liquidctl exited with code \(process.terminationStatus)" : errorText
            throw LiquidctlError.commandFailed(message)
        }

        return outputData
    }

    private static func parseFanChannel(from statusKey: String) -> String? {
        guard statusKey.hasSuffix(" speed") else { return nil }
        let prefix = statusKey.dropLast(" speed".count)
        guard prefix.hasPrefix("Fan ") else { return nil }
        guard let number = Int(prefix.dropFirst(4)) else { return nil }
        return LiquidctlIdentity.channelName(number: number)
    }
}
