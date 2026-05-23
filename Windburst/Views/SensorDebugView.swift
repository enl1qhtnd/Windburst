import SwiftUI
import WindburstShared

struct SensorDebugView: View {
    @ObservedObject var appState: AppState
    @State private var rawKeys: [String: String] = [:]
    @State private var isLoading = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sensor Debug")
                    .font(.headline)
                Spacer()
                Button(isLoading ? "Loading..." : "Dump SMC Keys") {
                    Task { await loadRawKeys() }
                }
                .disabled(isLoading)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusMessage.contains("error") || statusMessage.contains("no keys") ? .red : .secondary)
            }

            if sortedEntries.isEmpty && !isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "thermometer.medium.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No SMC keys loaded")
                        .font(.headline)
                    Text("Click Dump SMC Keys to read from AppleSMC/VirtualSMC.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Table(sortedEntries) {
                    TableColumn("Key") { entry in
                        Text(entry.key)
                            .font(.system(.body, design: .monospaced))
                    }
                    TableColumn("Live") { entry in
                        if let sensor = appState.monitor.sensor(named: entry.key),
                           let temp = sensor.temperature {
                            Text(TemperatureFormatter.string(temp, unit: appState.settings.temperatureUnit, decimals: 1))
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                        }
                    }
                    TableColumn("Raw") { entry in
                        Text(entry.value)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 180)
            }
        }
        .task {
            await loadRawKeys()
        }
    }

    private struct KeyEntry: Identifiable {
        let key: String
        let value: String
        var id: String { key }
    }

    private var sortedEntries: [KeyEntry] {
        rawKeys.keys.sorted().map { KeyEntry(key: $0, value: rawKeys[$0] ?? "") }
    }

    @MainActor
    private func loadRawKeys() async {
        isLoading = true
        defer { isLoading = false }

        let result = await appState.monitor.dumpSMCKeys()
        rawKeys = result.keys
        statusMessage = result.statusMessage

        if rawKeys.isEmpty {
            await appState.monitor.refreshDiscovery()
            for sensor in appState.monitor.sensors {
                rawKeys[sensor.key] = sensor.temperature.map { String(format: "%.1f°C", $0) } ?? "n/a"
            }
            if !rawKeys.isEmpty {
                statusMessage = "Showing \(rawKeys.count) discovered sensors from monitor."
            }
        }
    }
}

struct FirstRunView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Windburst")
                .font(.title.bold())

            Text("Windburst controls fans through a privileged helper. Click Register Helper — ad-hoc builds will ask for your password. Signed builds also require approval under Background Items in System Settings.")
                .foregroundStyle(.secondary)

            if let error = appState.helperClient.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if appState.helperClient.isConnected {
                Label("Helper connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            GroupBox("Hackintosh checklist") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("VirtualSMC.kext", systemImage: "checkmark.circle")
                    Label("SMCProcessor.kext (CPU temps)", systemImage: "checkmark.circle")
                    Label("SMCSuperIO.kext (fan headers)", systemImage: "checkmark.circle")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Register Helper") {
                Task { await appState.helperClient.registerHelperIfNeeded() }
            }
            .buttonStyle(.borderedProminent)

            Button("Open Background Items Settings") {
                SystemSettingsOpener.openBackgroundItems()
            }

            HStack {
                Spacer()
                Button("Continue") {
                    appState.settingsStore.update { $0.hasCompletedFirstRun = true }
                    appState.showFirstRun = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
