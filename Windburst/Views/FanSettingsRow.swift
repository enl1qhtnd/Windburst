import SwiftUI
import WindburstShared

struct FanSettingsRow: View {
    let fan: Fan
    @ObservedObject var appState: AppState
    @State private var customName: String
    @State private var minRPMText: String
    @State private var maxRPMText: String

    init(fan: Fan, appState: AppState) {
        self.fan = fan
        self.appState = appState
        let preferences = appState.fanPreferencesStore.preferences(for: fan.index)
        _customName = State(initialValue: preferences.displayName ?? fan.name)
        _minRPMText = State(initialValue: preferences.userMinRPM.map(String.init) ?? "")
        _maxRPMText = State(initialValue: preferences.userMaxRPM.map(String.init) ?? "")
    }

    private var preferences: FanIndividualPreferences {
        appState.fanPreferencesStore.preferences(for: fan.index)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preferences.displayName ?? fan.name)
                        .font(.headline)
                    Text("\(fan.controlSource == .liquidctl ? fan.name : "Fan \(fan.index + 1)") · \(fan.currentRPM) RPM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Visible", isOn: Binding(
                    get: { !preferences.isHidden },
                    set: { visible in
                        appState.fanPreferencesStore.update(for: fan.index) {
                            $0.isHidden = !visible
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .help(preferences.isHidden ? "Show fan" : "Hide fan")
            }

            MiniChartView(
                title: "RPM",
                samples: appState.monitor.rpmHistory(for: fan.index),
                color: .teal,
                yRange: MetricChartScale.rpmRange(for: fan)
            )

            TextField("Display name", text: $customName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { persistDisplayName() }

            HStack {
                TextField("Min RPM", text: $minRPMText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                TextField("Max RPM", text: $maxRPMText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Button("Apply Limits") {
                    persistRPMLimits()
                }
                .font(.caption)
            }

            Text("Hardware range: \(fan.minRPM)–\(fan.maxRPM) RPM")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

    private func persistDisplayName() {
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.fanPreferencesStore.update(for: fan.index) {
            $0.displayName = trimmed.isEmpty ? nil : trimmed
        }
    }

    private func persistRPMLimits() {
        let minRPM = Int(minRPMText.trimmingCharacters(in: .whitespacesAndNewlines))
        let maxRPM = Int(maxRPMText.trimmingCharacters(in: .whitespacesAndNewlines))
        appState.fanPreferencesStore.update(for: fan.index) {
            $0.userMinRPM = minRPM
            $0.userMaxRPM = maxRPM
        }
    }
}
