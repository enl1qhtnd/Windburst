import Foundation
import Combine
import WindburstShared
import Darwin

@MainActor
final class MonitorEngine: ObservableObject {
    private static let historyWindowSeconds = MetricChartScale.historyWindowSeconds
    @Published var sensors: [Sensor] = []
    @Published var fans: [Fan] = []
    @Published var primaryTemperature: Double?
    @Published var primarySensorKey: String?
    @Published var cpuUsagePercent: Double = 0
    @Published var uptime: TimeInterval = 0
    @Published var isConnected = false
    @Published var lastError: String?
    @Published var activeCurveTargets: [Int: Int] = [:]
    @Published private(set) var temperatureHistory: [MetricSample] = []
    @Published private(set) var cpuHistory: [MetricSample] = []
    @Published private(set) var fanHistory: [Int: [MetricSample]] = [:]

    private var tempHistory = RingBuffer<MetricSample>(
        capacity: MetricChartScale.historySampleCapacity,
        defaultValue: MetricSample(value: 0)
    )
    private var cpuHistoryBuffer = RingBuffer<MetricSample>(
        capacity: MetricChartScale.historySampleCapacity,
        defaultValue: MetricSample(value: 0)
    )
    private var fanHistoryBuffers: [Int: RingBuffer<MetricSample>] = [:]
    private var fanPreferences = FanPreferencesCollection()
    private var fanOverrideTargets: [Int: Int] = [:]
    private let smcDriver = SMCDriver()
    private let helperClient = HelperClient.shared
    private let liquidctlClient = LiquidctlClient.shared
    private var pollTimer: Timer?
    private var isPolling = false
    private var settings: AppSettings

    var onDidPoll: (() -> Void)?

    init(settings: AppSettings = .default) {
        self.settings = settings
        liquidctlClient.updateConfiguration(customPath: settings.liquidctlPath)
        LiquidctlCurveLoop.shared.configureTemperatureReader { [weak self] sensorKey in
            guard let self else { return nil }
            return self.sensors.first(where: { $0.key == sensorKey })?.temperature
        }
    }

    func start(settings: AppSettings) {
        self.settings = settings
        stop()
        let interval = max(settings.refreshIntervalSeconds, 1)
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.poll()
            }
        }
        pollTimer?.fire()
        if let timer = pollTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func updateSettings(_ settings: AppSettings) {
        let intervalChanged = self.settings.refreshIntervalSeconds != settings.refreshIntervalSeconds
        let backendChanged = self.settings.fanControlBackend != settings.fanControlBackend
        self.settings = settings
        liquidctlClient.updateConfiguration(customPath: settings.liquidctlPath)
        if let key = settings.primarySensorKey {
            primarySensorKey = key
        }
        if intervalChanged {
            start(settings: settings)
        }
        if backendChanged {
            if settings.fanControlBackend == .liquidctl {
                LiquidctlCurveLoop.shared.stopAll()
            }
            Task { await poll() }
        }
    }

    func updateFanPreferences(_ preferences: FanPreferencesCollection) {
        fanPreferences = preferences
        applyFanPreferences()
    }

    func rpmHistory(for fanIndex: Int) -> [MetricSample] {
        fanHistory[fanIndex] ?? []
    }

    func refreshDiscovery() async {
        await poll()
    }

    func setFanOverrideTarget(fanIndex: Int, rpm: Int?) {
        if let rpm {
            fanOverrideTargets[fanIndex] = rpm
        } else {
            fanOverrideTargets.removeValue(forKey: fanIndex)
        }
        applyActiveCurveOverlay()
    }

    func dumpSMCKeys() async -> (keys: [String: String], statusMessage: String) {
        let smc = SMCDriver()
        do {
            let keys = try smc.dumpAllKeys()
            return (keys, "Found \(keys.count) SMC keys.")
        } catch {
            if helperClient.isConnected {
                let helperKeys = await helperClient.readAllKeys()
                if !helperKeys.isEmpty {
                    return (helperKeys, "Read \(helperKeys.count) keys via helper.")
                }
            }
            return ([:], error.localizedDescription)
        }
    }

    private func poll() async {
        guard !isPolling else { return }
        isPolling = true
        defer {
            isPolling = false
            onDidPoll?()
        }

        uptime = ProcessInfo.processInfo.systemUptime
        cpuUsagePercent = Self.readCPUUsage()

        do {
            if !smcDriver.isConnected {
                try smcDriver.open()
            }
        } catch {
            lastError = error.localizedDescription
        }

        isConnected = smcDriver.isConnected || helperClient.isConnected || liquidctlClient.isAvailable

        if settings.fanControlBackend == .liquidctl {
            fans = await liquidctlClient.discoverFans()
            if smcDriver.isConnected || helperClient.isConnected {
                do {
                    if !smcDriver.isConnected {
                        try smcDriver.open()
                    }
                    sensors = try smcDriver.discoverSensors()
                } catch {
                    lastError = error.localizedDescription
                }
            }
            if helperClient.isConnected {
                let helperSensors = await helperClient.discoverSensors()
                sensors = mergeSensors(sensors, helperSensors)
            }
        } else {
            if smcDriver.isConnected {
                do {
                    sensors = try smcDriver.discoverSensors()
                    fans = try smcDriver.discoverFans()
                } catch {
                    lastError = error.localizedDescription
                }
            }

            if helperClient.isConnected {
                let helperSensors = await helperClient.discoverSensors()
                let helperFans = await helperClient.discoverFans()
                sensors = mergeSensors(sensors, helperSensors)
                fans = helperFans.isEmpty ? fans : helperFans
            }
        }

        if settings.fanControlBackend == .liquidctl {
            activeCurveTargets = LiquidctlCurveLoop.shared.activeTargets
        } else {
            activeCurveTargets = await helperClient.getActiveCurveStatus()
        }
        if sensors.isEmpty && fans.isEmpty && lastError == nil && !isConnected {
            if settings.fanControlBackend == .liquidctl {
                lastError = liquidctlClient.lastError ?? "liquidctl is not available."
            } else {
                lastError = "Could not open AppleSMC/VirtualSMC. Check that VirtualSMC.kext and sensor plugins are loaded."
            }
        }
        applyActiveCurveOverlay()
        applyFanPreferences()

        if primarySensorKey == nil {
            primarySensorKey = settings.primarySensorKey
                ?? SMCKeyCatalog.defaultPrimarySensor(from: sensors)?.key
        }

        if let key = primarySensorKey,
           let sensor = sensors.first(where: { $0.key == key }),
           let temp = sensor.temperature {
            primaryTemperature = temp
        } else if let maxTemp = sensors.compactMap(\.temperature).max() {
            primaryTemperature = maxTemp
        } else {
            primaryTemperature = nil
        }

        let now = Date()
        recordFanHistory(at: now)
        let cutoff = now.addingTimeInterval(-Self.historyWindowSeconds)
        tempHistory.append(MetricSample(timestamp: now, value: primaryTemperature ?? 0))
        temperatureHistory = tempHistory.elements.filter { $0.timestamp >= cutoff }
        cpuHistoryBuffer.append(MetricSample(timestamp: now, value: cpuUsagePercent))
        cpuHistory = cpuHistoryBuffer.elements.filter { $0.timestamp >= cutoff }

        if activeCurveTargets.isEmpty {
            if settings.fanControlBackend == .liquidctl {
                activeCurveTargets = LiquidctlCurveLoop.shared.activeTargets
            } else {
                activeCurveTargets = await helperClient.getActiveCurveStatus()
            }
        }
    }

    private func applyActiveCurveOverlay() {
        for index in fans.indices {
            let fanIndex = fans[index].index
            if let target = fanOverrideTargets[fanIndex] {
                fans[index].controlMode = .manual
                fans[index].targetRPM = target
            } else if let target = activeCurveTargets[fanIndex] {
                fans[index].controlMode = .curve
                fans[index].targetRPM = target
            }
        }
    }

    private func applyFanPreferences() {
        for index in fans.indices {
            let preferences = fanPreferences.preferences(for: fans[index].index)
            if let displayName = preferences.displayName, !displayName.isEmpty {
                fans[index].name = displayName
            }
            fans[index].userMinRPM = preferences.userMinRPM
            fans[index].userMaxRPM = preferences.userMaxRPM
        }
    }

    private func recordFanHistory(at timestamp: Date) {
        let cutoff = timestamp.addingTimeInterval(-Self.historyWindowSeconds)
        var updatedHistory = fanHistory

        for fan in fans {
            if fanHistoryBuffers[fan.index] == nil {
                fanHistoryBuffers[fan.index] = RingBuffer(
                    capacity: MetricChartScale.historySampleCapacity,
                    defaultValue: MetricSample(value: 0)
                )
            }
            fanHistoryBuffers[fan.index]?.append(MetricSample(timestamp: timestamp, value: Double(fan.currentRPM)))
            updatedHistory[fan.index] = fanHistoryBuffers[fan.index]?.elements.filter { $0.timestamp >= cutoff } ?? []
        }

        fanHistory = updatedHistory
    }

    func sensor(named key: String) -> Sensor? {
        sensors.first { $0.key == key }
    }

    private func mergeSensors(_ local: [Sensor], _ remote: [Sensor]) -> [Sensor] {
        var merged = Dictionary(uniqueKeysWithValues: local.map { ($0.key, $0) })
        for sensor in remote where sensor.isAvailable {
            merged[sensor.key] = sensor
        }
        return merged.values.sorted {
            SMCKeyCatalog.temperaturePriority(for: $0.key) < SMCKeyCatalog.temperaturePriority(for: $1.key)
        }
    }

    nonisolated private static func readCPUUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        var totalUsage: Double = 0

        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threads = threadList else {
            return 0
        }

        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_act_t>.stride))
        }

        for index in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                    thread_info(threads[index], thread_flavor_t(THREAD_BASIC_INFO), intPointer, &count)
                }
            }
            guard result == KERN_SUCCESS else { continue }
            if (info.flags & TH_FLAGS_IDLE) == 0 {
                totalUsage += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }

        return min(totalUsage, 100)
    }
}
