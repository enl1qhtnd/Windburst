import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WindburstShared

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settingsStore: SettingsStore
    @State private var importExportMessage: String?

    init(appState: AppState) {
        self.appState = appState
        self.settingsStore = appState.settingsStore
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            fansTab
                .tabItem { Label("Fans", systemImage: "fan") }
            sensorsTab
                .tabItem { Label("Sensors", systemImage: "thermometer") }
            presetsTab
                .tabItem { Label("Presets", systemImage: "slider.horizontal.3") }
            helperTab
                .tabItem { Label("Helper", systemImage: "lock.shield") }
        }
        .frame(width: 520, height: 480)
        .padding(12)
    }

    private var generalTab: some View {
        Form {
            Picker("Temperature unit", selection: settingsBinding(\.temperatureUnit)) {
                ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }

            Toggle("Show RPM in menu bar", isOn: settingsBinding(\.showRPMInMenuBar))

            Picker("Refresh interval", selection: settingsBinding(\.refreshIntervalSeconds)) {
                ForEach(AppSettings.refreshIntervalChoices, id: \.self) { seconds in
                    Text(refreshIntervalLabel(seconds)).tag(seconds)
                }
            }

            Toggle("Launch at login", isOn: settingsBinding(\.launchAtLogin))
                .onChange(of: settingsStore.settings.launchAtLogin) { enabled in
                    try? LaunchAtLoginManager.setEnabled(enabled)
                }

            Toggle("High temperature alerts", isOn: settingsBinding(\.highTempAlertEnabled))
            Stepper(
                "Alert threshold: \(Int(settingsStore.settings.highTempThreshold))°C",
                value: settingsBinding(\.highTempThreshold),
                in: 60...100,
                step: 1
            )

            Toggle("Link fans to shared curve", isOn: settingsBinding(\.linkFans))
            Toggle("Safe startup (50% until first valid read)", isOn: settingsBinding(\.safeStartupEnabled))

            Picker("Fan control backend", selection: settingsBinding(\.fanControlBackend)) {
                ForEach(FanControlBackend.allCases, id: \.self) { backend in
                    Text(backend.rawValue).tag(backend)
                }
            }

            if settingsStore.settings.fanControlBackend == .liquidctl {
                TextField("liquidctl path (optional)", text: Binding(
                    get: { settingsStore.settings.liquidctlPath ?? "" },
                    set: { newValue in
                        settingsStore.update {
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            $0.liquidctlPath = trimmed.isEmpty ? nil : trimmed
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)

                LabeledContent("liquidctl status") {
                    Image(systemName: appState.liquidctlClient.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(appState.liquidctlClient.isAvailable ? .green : .orange)
                }

                if let path = appState.liquidctlClient.resolvedPath {
                    Text("Using \(path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = appState.liquidctlClient.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Initialize liquidctl Devices") {
                    Task {
                        try? await appState.liquidctlClient.initializeAll()
                        await appState.monitor.refreshDiscovery()
                    }
                }

                Text("When liquidctl is selected, only USB/HID devices managed by liquidctl are shown. SMC fans are hidden. Temperature curves still use VirtualSMC sensors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: settingsStore.settings) { newSettings in
            appState.monitor.updateSettings(newSettings)
        }
    }

    private func refreshIntervalLabel(_ seconds: Double) -> String {
        if seconds == 1 {
            return "1 second"
        }
        return "\(Int(seconds)) seconds"
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                settingsStore.update { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private var fansTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if appState.monitor.fans.isEmpty {
                    Text("No fans discovered yet.")
                        .foregroundStyle(.secondary)
                    Button("Refresh") {
                        Task { await appState.monitor.refreshDiscovery() }
                    }
                } else {
                    ForEach(appState.monitor.fans) { fan in
                        FanSettingsRow(fan: fan, appState: appState)
                    }
                }
            }
            .padding(8)
        }
    }

    private var sensorsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Primary sensor", selection: Binding(
                get: { settingsStore.settings.primarySensorKey ?? "" },
                set: { newValue in
                    settingsStore.update { $0.primarySensorKey = newValue.isEmpty ? nil : newValue }
                }
            )) {
                Text("Automatic").tag("")
                ForEach(appState.monitor.sensors.filter(\.isAvailable), id: \.key) { sensor in
                    Text("\(sensor.name) (\(sensor.key))").tag(sensor.key)
                }
            }

            SensorDebugView(appState: appState)

            if let error = appState.monitor.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Refresh Sensors") {
                Task { await appState.monitor.refreshDiscovery() }
            }
        }
        .padding(8)
    }

    private var presetsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(appState.presetStore.presets, id: \.id) { preset in
                HStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(PresetTheme.accentColor(for: preset))
                        .frame(width: 4, height: 32)
                        .opacity(preset.isBuiltIn ? 1 : 0.35)

                    VStack(alignment: .leading) {
                        Text(preset.name).font(.headline)
                        Text("\(preset.curve.points.count) points")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit") {
                        appState.openCurveEditor(curve: preset.curve, presetID: preset.id)
                    }
                    if !preset.isBuiltIn {
                        Button("Delete", role: .destructive) {
                            appState.presetStore.deletePreset(id: preset.id)
                        }
                    }
                }
                .listRowBackground(PresetTheme.cardBackground(for: preset))
            }

            HStack {
                Button("New Curve") {
                    appState.openCurveEditor(curve: FanCurve.defaultCurve(name: "New Curve"))
                }
                Button("Export Presets") { exportPresets() }
                Button("Import Presets") { importPresets() }
            }

            if let importExportMessage {
                Text(importExportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }

    private var helperTab: some View {
        Form {
            LabeledContent("Helper connected") {
                Image(systemName: appState.helperClient.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(appState.helperClient.isConnected ? .green : .orange)
            }
            LabeledContent("Registration status") {
                Text(statusLabel)
            }
            Text(appState.helperClient.registrationStatus.userFacingDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = appState.helperClient.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Register Helper") {
                Task { await appState.helperClient.registerHelperIfNeeded() }
            }

            Button("Open Background Items Settings") {
                SystemSettingsOpener.openBackgroundItems()
            }

            Text("Ad-hoc builds install the helper with your administrator password (no Background Items entry). Signed builds use SMAppService and appear under Background Items.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusLabel: String {
        switch appState.helperClient.registrationStatus {
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Needs approval"
        case .notRegistered:
            return "Not registered"
        case .notFound:
            return "Helper missing"
        case .failed:
            return "Failed"
        }
    }

    private func exportPresets() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "WindburstPresets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let document = appState.presetStore.exportDocument()
        if let data = try? JSONEncoder.pretty.encode(document) {
            try? data.write(to: url)
            importExportMessage = "Exported presets to \(url.lastPathComponent)"
        }
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(PresetExportDocument.self, from: data) else {
            importExportMessage = "Import failed"
            return
        }
        appState.presetStore.importDocument(document)
        importExportMessage = "Imported \(document.presets.count) presets"
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
