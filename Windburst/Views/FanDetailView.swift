import SwiftUI
import WindburstShared

struct FanDetailView: View {
    let fan: Fan
    @ObservedObject var appState: AppState
    @State private var manualRPM: Double
    @State private var isOverriding = false
    @State private var overridePercent: Double
    @State private var showSettings = false
    @State private var customName: String
    @State private var minRPMText: String
    @State private var maxRPMText: String

    init(fan: Fan, appState: AppState) {
        self.fan = fan
        self.appState = appState
        let preferences = appState.fanPreferencesStore.preferences(for: fan.index)
        _manualRPM = State(initialValue: Double(fan.currentRPM))
        _overridePercent = State(initialValue: fan.rpmPercent * 100)
        _customName = State(initialValue: preferences.displayName ?? fan.name)
        _minRPMText = State(initialValue: preferences.userMinRPM.map(String.init) ?? "")
        _maxRPMText = State(initialValue: preferences.userMaxRPM.map(String.init) ?? "")
    }

    private var preferences: FanIndividualPreferences {
        appState.fanPreferencesStore.preferences(for: fan.index)
    }

    private var liveFan: Fan {
        appState.monitor.fans.first(where: { $0.index == fan.index }) ?? fan
    }

    private var assignedPreset: FanPreset? {
        appState.presetStore.preset(id: appState.assignedCurveID(for: fan.index))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            MiniChartView(
                title: "RPM",
                samples: appState.monitor.rpmHistory(for: fan.index),
                color: .teal,
                yRange: MetricChartScale.rpmRange(for: fan)
            )

            HStack {
                Text("\(fan.currentRPM) RPM")
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Text("max \(fan.effectiveMaxRPM)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: isOverriding ? overridePercent / 100 : fan.rpmPercent)
                .tint(progressTint)

            if isOverriding {
                overrideControls
            } else if fan.controlMode == .manual {
                manualControls
            }

            if !isOverriding {
                curveControls
            }

            settingsSection
        }
        .padding(12)
        .background(PresetTheme.cardBackground(for: assignedPreset), in: RoundedRectangle(cornerRadius: 10))
        .onAppear {
            isOverriding = appState.isFanOverridden(fan.index)
            if isOverriding {
                overridePercent = fan.rpmPercent * 100
            }
        }
        .onChange(of: fan.currentRPM) { newValue in
            if fan.controlMode == .manual, !isOverriding {
                manualRPM = Double(newValue)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(displayName)
                .font(.headline)
            Spacer()
            Button {
                appState.fanPreferencesStore.update(for: fan.index) { $0.isHidden = true }
            } label: {
                Image(systemName: "eye.slash")
            }
            .buttonStyle(.borderless)
            .help("Hide fan")

            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: showSettings ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Fan settings")

            overrideButton
        }
    }

    private var overrideButton: some View {
        Button {
            Task {
                if isOverriding {
                    await appState.endFanOverride(for: fan.index)
                    isOverriding = false
                } else {
                    overridePercent = liveFan.rpmPercent * 100
                    await appState.startFanOverride(for: fan.index, initialPercent: overridePercent)
                    isOverriding = true
                }
            }
        } label: {
            Text(isOverriding ? "Done" : "Override")
                .font(.caption2.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(isOverriding ? .purple : .accentColor)
        .disabled(!appState.canControlFans)
        .help(isOverriding ? "Restore assigned curve" : "Temporarily set fan speed (0–100%)")
    }

    private var displayName: String {
        if let name = preferences.displayName, !name.isEmpty {
            return name
        }
        return fan.name
    }

    private var overrideControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Override")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
                Spacer()
                Text("\(Int(overridePercent))% · \(overrideRPM) RPM")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $overridePercent, in: 0...100, step: 1)
                .tint(.purple)
                .onChange(of: overridePercent) { newValue in
                    Task {
                        try? await appState.setFanOverridePercent(
                            for: fan.index,
                            percent: newValue,
                            fan: liveFan
                        )
                    }
                }
        }
    }

    private var overrideRPM: Int {
        let range = liveFan.effectiveMaxRPM - liveFan.effectiveMinRPM
        return liveFan.effectiveMinRPM + Int(round((overridePercent / 100.0) * Double(range)))
    }

    private var manualControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Slider(
                value: $manualRPM,
                in: Double(fan.effectiveMinRPM)...Double(fan.effectiveMaxRPM),
                step: 50
            ) {
                Text("Manual RPM")
            } minimumValueLabel: {
                Text("\(fan.effectiveMinRPM)")
                    .font(.caption2)
            } maximumValueLabel: {
                Text("\(fan.effectiveMaxRPM)")
                    .font(.caption2)
            }
            .onChange(of: manualRPM) { newValue in
                Task {
                    try? await appState.setManualRPM(for: fan.index, rpm: Int(newValue))
                }
            }
        }
    }

    private var curveControls: some View {
        HStack(spacing: 8) {
            Picker("Curve", selection: Binding(
                get: { appState.assignedCurveID(for: fan.index) },
                set: { newID in
                    Task { await appState.setCurve(curveID: newID, for: fan.index) }
                }
            )) {
                ForEach(appState.presetStore.presets, id: \.id) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .labelsHidden()

            Button("Edit Curve") {
                let curveID = appState.assignedCurveID(for: fan.index)
                if let preset = appState.presetStore.preset(id: curveID) {
                    appState.openCurveEditor(curve: preset.curve, presetID: preset.id)
                }
            }
            .font(.caption)
            .disabled(!appState.canControlFans)
        }
    }

    @ViewBuilder
    private var settingsSection: some View {
        if showSettings {
            VStack(alignment: .leading, spacing: 8) {
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

                if preferences.userMinRPM != nil || preferences.userMaxRPM != nil {
                    Button("Reset Limits") {
                        minRPMText = ""
                        maxRPMText = ""
                        appState.fanPreferencesStore.update(for: fan.index) {
                            $0.userMinRPM = nil
                            $0.userMaxRPM = nil
                        }
                    }
                    .font(.caption)
                }
            }
            .padding(.top, 4)
        }
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

    private var progressTint: Color {
        if isOverriding { return .purple }
        if fan.controlMode == .manual { return .blue }
        return PresetTheme.accentColor(for: assignedPreset)
    }
}
