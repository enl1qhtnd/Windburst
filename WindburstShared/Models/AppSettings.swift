import Foundation

public enum TemperatureUnit: String, Codable, CaseIterable, Sendable {
    case celsius = "Celsius"
    case fahrenheit = "Fahrenheit"

    public func convert(_ celsius: Double) -> Double {
        switch self {
        case .celsius: return celsius
        case .fahrenheit: return celsius * 9.0 / 5.0 + 32.0
        }
    }

    public var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }
}

public struct AppSettings: Codable, Sendable, Equatable {
    public static let refreshIntervalChoices: [Double] = [1, 2, 5, 10, 30]

    public var primarySensorKey: String?
    public var temperatureUnit: TemperatureUnit
    public var showRPMInMenuBar: Bool
    public var showCPUSparkline: Bool
    public var refreshIntervalSeconds: Double
    public var launchAtLogin: Bool
    public var highTempAlertEnabled: Bool
    public var highTempThreshold: Double
    public var linkFans: Bool
    public var manualOverrideMinutes: Int
    public var safeStartupEnabled: Bool
    public var hasCompletedFirstRun: Bool
    public var selectedPresetName: String
    public var fanControlBackend: FanControlBackend
    public var liquidctlPath: String?

    public init(
        primarySensorKey: String? = nil,
        temperatureUnit: TemperatureUnit = .celsius,
        showRPMInMenuBar: Bool = true,
        showCPUSparkline: Bool = true,
        refreshIntervalSeconds: Double = 2,
        launchAtLogin: Bool = false,
        highTempAlertEnabled: Bool = true,
        highTempThreshold: Double = 85,
        linkFans: Bool = false,
        manualOverrideMinutes: Int = 15,
        safeStartupEnabled: Bool = true,
        hasCompletedFirstRun: Bool = false,
        selectedPresetName: String = "",
        fanControlBackend: FanControlBackend = .smc,
        liquidctlPath: String? = nil
    ) {
        self.primarySensorKey = primarySensorKey
        self.temperatureUnit = temperatureUnit
        self.showRPMInMenuBar = showRPMInMenuBar
        self.showCPUSparkline = showCPUSparkline
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.launchAtLogin = launchAtLogin
        self.highTempAlertEnabled = highTempAlertEnabled
        self.highTempThreshold = highTempThreshold
        self.linkFans = linkFans
        self.manualOverrideMinutes = manualOverrideMinutes
        self.safeStartupEnabled = safeStartupEnabled
        self.hasCompletedFirstRun = hasCompletedFirstRun
        self.selectedPresetName = selectedPresetName
        self.fanControlBackend = fanControlBackend
        self.liquidctlPath = liquidctlPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            primarySensorKey: try container.decodeIfPresent(String.self, forKey: .primarySensorKey),
            temperatureUnit: try container.decodeIfPresent(TemperatureUnit.self, forKey: .temperatureUnit) ?? .celsius,
            showRPMInMenuBar: try container.decodeIfPresent(Bool.self, forKey: .showRPMInMenuBar) ?? true,
            showCPUSparkline: try container.decodeIfPresent(Bool.self, forKey: .showCPUSparkline) ?? true,
            refreshIntervalSeconds: try container.decodeIfPresent(Double.self, forKey: .refreshIntervalSeconds) ?? 2,
            launchAtLogin: try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false,
            highTempAlertEnabled: try container.decodeIfPresent(Bool.self, forKey: .highTempAlertEnabled) ?? true,
            highTempThreshold: try container.decodeIfPresent(Double.self, forKey: .highTempThreshold) ?? 85,
            linkFans: try container.decodeIfPresent(Bool.self, forKey: .linkFans) ?? false,
            manualOverrideMinutes: try container.decodeIfPresent(Int.self, forKey: .manualOverrideMinutes) ?? 15,
            safeStartupEnabled: try container.decodeIfPresent(Bool.self, forKey: .safeStartupEnabled) ?? true,
            hasCompletedFirstRun: try container.decodeIfPresent(Bool.self, forKey: .hasCompletedFirstRun) ?? false,
            selectedPresetName: try container.decodeIfPresent(String.self, forKey: .selectedPresetName) ?? "",
            fanControlBackend: try container.decodeIfPresent(FanControlBackend.self, forKey: .fanControlBackend) ?? .smc,
            liquidctlPath: try container.decodeIfPresent(String.self, forKey: .liquidctlPath)
        )
    }

    public static let `default` = AppSettings()
}
