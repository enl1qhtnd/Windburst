import SwiftUI
import Combine
import WindburstShared

@MainActor
final class AppState: ObservableObject {
    let monitor = MonitorEngine()
    let settingsStore = SettingsStore.shared
    let presetStore = PresetStore.shared
    let fanPreferencesStore = FanPreferencesStore.shared
    let helperClient = HelperClient.shared
    let liquidctlClient = LiquidctlClient.shared
    let curveEngine = CurveEngineService.shared

    @Published var showFirstRun = false
    @Published private(set) var activeFanOverrides: Set<Int> = []

    var settings: AppSettings { settingsStore.settings }

    var canControlFans: Bool {
        switch settings.fanControlBackend {
        case .smc:
            return helperClient.isConnected
        case .liquidctl:
            return liquidctlClient.isAvailable
        }
    }

    var fanControlStatusMessage: String? {
        switch settings.fanControlBackend {
        case .smc where !helperClient.isConnected:
            return "Helper not connected"
        case .liquidctl where !liquidctlClient.isAvailable:
            return liquidctlClient.lastError ?? "liquidctl not available"
        default:
            return nil
        }
    }

    private struct FanOverrideContext {
        var curveID: UUID?
    }

    private var fanOverrideContexts: [Int: FanOverrideContext] = [:]

    private var statusBarController: StatusBarController?
    private var settingsWindow: NSWindow?
    private var curveEditorWindow: NSWindow?
    private var firstRunWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init() {
        monitor.onDidPoll = { [weak self] in
            self?.tickAlerts()
        }

        monitor.updateFanPreferences(fanPreferencesStore.collection)

        monitor.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        settingsStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        fanPreferencesStore.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                self.monitor.updateFanPreferences(self.fanPreferencesStore.collection)
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        presetStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func bootstrap() {
        showFirstRun = !settings.hasCompletedFirstRun
        statusBarController = StatusBarController(appState: self)
        liquidctlClient.updateConfiguration(customPath: settings.liquidctlPath)
        monitor.start(settings: settings)
        AlertManager.shared.requestAuthorization()

        Task {
            helperClient.refreshRegistrationStatus()
            if helperClient.registrationStatus.isOperational {
                helperClient.connect()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            await monitor.refreshDiscovery()
            migrateLegacyPresetSelectionIfNeeded()
            if helperClient.isConnected || settings.fanControlBackend == .liquidctl {
                await applyAllAssignedCurves()
            }
        }

        if showFirstRun {
            presentFirstRun()
        }
    }

    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Windburst Settings"
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView(appState: self))
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openCurveEditor(curve: FanCurve? = nil, presetID: UUID? = nil) {
        let resolvedPresetID = presetID ?? curve.flatMap { curve in
            presetStore.presets.first { $0.curve.id == curve.id }?.id
        }
        let resolvedCurve: FanCurve
        if let curve {
            resolvedCurve = curve
        } else if let presetID, let preset = presetStore.preset(id: presetID) {
            resolvedCurve = preset.curve
        } else {
            resolvedCurve = FanCurve.defaultCurve(name: "New Curve")
        }

        if curveEditorWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Fan Curve Editor"
            window.center()
            window.isReleasedWhenClosed = false
            curveEditorWindow = window
        }

        curveEditorWindow?.contentView = NSHostingView(
            rootView: CurveEditorView(appState: self, curve: resolvedCurve, presetID: resolvedPresetID)
        )
        curveEditorWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func assignedCurveID(for fanIndex: Int) -> UUID {
        fanPreferencesStore.preferences(for: fanIndex).assignedCurveID ?? FanPreset.defaultCurveID
    }

    func assignedCurveName(for fanIndex: Int) -> String {
        presetStore.preset(id: assignedCurveID(for: fanIndex))?.name ?? "Balanced"
    }

    func setCurve(curveID: UUID, for fanIndex: Int) async {
        let fanIndices = affectedFanIndices(changedFanIndex: fanIndex)
        for index in fanIndices {
            fanPreferencesStore.update(for: index) { $0.assignedCurveID = curveID }
        }
        await applyCurve(curveID: curveID, to: fanIndices)
    }

    func saveCurveProfile(_ curve: FanCurve, presetID: UUID?, name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        var updatedCurve = curve
        updatedCurve.name = trimmedName

        let savedID: UUID
        if let presetID, var preset = presetStore.preset(id: presetID) {
            preset.name = trimmedName
            preset.curve = updatedCurve
            presetStore.upsert(preset)
            savedID = presetID
        } else {
            let preset = presetStore.createPreset(name: trimmedName, curve: updatedCurve)
            savedID = preset.id
        }

        Task {
            let affectedFans = monitor.fans
                .filter { assignedCurveID(for: $0.index) == savedID }
                .map(\.index)
            if !affectedFans.isEmpty {
                await applyCurve(curveID: savedID, to: affectedFans)
            }
        }
    }

    func applyAllAssignedCurves() async {
        let fans = monitor.fans
        guard !fans.isEmpty else { return }

        var curveToFans: [UUID: [Int]] = [:]
        for fan in fans {
            let curveID = assignedCurveID(for: fan.index)
            curveToFans[curveID, default: []].append(fan.index)
        }

        for (curveID, fanIndices) in curveToFans {
            await applyCurve(curveID: curveID, to: fanIndices)
        }
    }

    func setManualRPM(for fanIndex: Int, rpm: Int, refreshDiscovery: Bool = true) async throws {
        guard let fan = monitor.fans.first(where: { $0.index == fanIndex }) else { return }
        try await curveEngine.setManualRPM(fan: fan, rpm: rpm, backend: settings.fanControlBackend)
        if refreshDiscovery {
            await monitor.refreshDiscovery()
        }
    }

    func isFanOverridden(_ fanIndex: Int) -> Bool {
        activeFanOverrides.contains(fanIndex)
    }

    func startFanOverride(for fanIndex: Int, initialPercent: Double? = nil) async {
        let curveID = assignedCurveID(for: fanIndex)
        fanOverrideContexts[fanIndex] = FanOverrideContext(curveID: curveID)
        activeFanOverrides.insert(fanIndex)

        await curveEngine.stopCurve(for: fanIndex, backend: settings.fanControlBackend)
        _ = await curveEngine.setManualMode(for: fanIndex, backend: settings.fanControlBackend)

        if settings.fanControlBackend == .liquidctl {
            LiquidctlCurveLoop.shared.setFanOverridden(fanIndex, overridden: true)
        }

        if let initialPercent,
           let fan = monitor.fans.first(where: { $0.index == fanIndex }) {
            try? await setFanOverridePercent(for: fanIndex, percent: initialPercent, fan: fan)
        } else {
            await monitor.refreshDiscovery()
        }
    }

    func setFanOverridePercent(for fanIndex: Int, percent: Double, fan: Fan) async throws {
        let clamped = min(max(percent, 0), 100)
        guard let liveFan = monitor.fans.first(where: { $0.index == fanIndex }) else { return }

        switch settings.fanControlBackend {
        case .liquidctl:
            LiquidctlCurveLoop.shared.setFanOverridden(fanIndex, overridden: true)
            try await liquidctlClient.setSpeedPercent(for: liveFan, percent: clamped)
            let range = liveFan.effectiveMaxRPM - liveFan.effectiveMinRPM
            let rpm = liveFan.effectiveMinRPM + Int(round((clamped / 100.0) * Double(range)))
            monitor.setFanOverrideTarget(fanIndex: fanIndex, rpm: rpm)
        case .smc:
            let range = fan.effectiveMaxRPM - fan.effectiveMinRPM
            let rpm = fan.effectiveMinRPM + Int(round((clamped / 100.0) * Double(range)))
            try await setManualRPM(for: fanIndex, rpm: rpm)
        }
    }

    func endFanOverride(for fanIndex: Int) async {
        let context = fanOverrideContexts.removeValue(forKey: fanIndex)
        activeFanOverrides.remove(fanIndex)

        if settings.fanControlBackend == .liquidctl {
            LiquidctlCurveLoop.shared.setFanOverridden(fanIndex, overridden: false)
            monitor.setFanOverrideTarget(fanIndex: fanIndex, rpm: nil)
        }

        let curveID = context?.curveID ?? assignedCurveID(for: fanIndex)
        await applyCurve(curveID: curveID, to: [fanIndex])
    }

    func tickAlerts() {
        AlertManager.shared.checkTemperature(monitor.primaryTemperature, settings: settings)
    }

    func quit() async {
        monitor.stop()
        if settings.fanControlBackend == .liquidctl {
            LiquidctlCurveLoop.shared.stopAll()
        } else {
            await helperClient.shutdown()
        }
        NSApplication.shared.terminate(nil)
    }

    private func migrateLegacyPresetSelectionIfNeeded() {
        let legacyName = settings.selectedPresetName
        if !legacyName.isEmpty, let preset = presetStore.preset(named: legacyName) {
            for fan in monitor.fans {
                fanPreferencesStore.update(for: fan.index) { $0.assignedCurveID = preset.id }
            }
            settingsStore.update { $0.selectedPresetName = "" }
        }
        ensureDefaultCurveAssignments()
    }

    private func ensureDefaultCurveAssignments() {
        for fan in monitor.fans {
            let preferences = fanPreferencesStore.preferences(for: fan.index)
            if preferences.assignedCurveID == nil {
                fanPreferencesStore.update(for: fan.index) {
                    $0.assignedCurveID = FanPreset.defaultCurveID
                }
            }
        }
    }

    private func affectedFanIndices(changedFanIndex: Int) -> [Int] {
        if settings.linkFans {
            return monitor.fans.map(\.index)
        }
        return [changedFanIndex]
    }

    private func applyCurve(curveID: UUID, to fanIndices: [Int]) async {
        let activeFanIndices = fanIndices.filter { !activeFanOverrides.contains($0) }
        guard let preset = presetStore.preset(id: curveID), !activeFanIndices.isEmpty else { return }
        let sensorKey = settings.primarySensorKey
            ?? monitor.primarySensorKey
            ?? SMCKeyCatalog.defaultPrimarySensor(from: monitor.sensors)?.key
            ?? "TC0P"

        var presetCopy = preset
        presetCopy.linkedFanIndices = activeFanIndices

        do {
            try await curveEngine.applyPreset(
                presetCopy,
                fans: monitor.fans,
                sensorKey: sensorKey,
                linkFans: false,
                backend: settings.fanControlBackend
            )
            await monitor.refreshDiscovery()
        } catch {
            helperClient.lastError = error.localizedDescription
        }
    }

    private func presentFirstRun() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Windburst Setup"
        window.center()
        window.contentView = NSHostingView(rootView: FirstRunView(appState: self))
        window.isReleasedWhenClosed = false
        firstRunWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
