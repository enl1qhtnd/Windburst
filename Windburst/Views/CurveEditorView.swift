import SwiftUI
import Charts
import WindburstShared

struct CurveEditorView: View {
    @ObservedObject var appState: AppState
    @State private var editingCurve: FanCurve
    @State private var selectedPointID: UUID?
    @State private var presetName: String
    let presetID: UUID?
    let isNewCurve: Bool

    init(appState: AppState, curve: FanCurve, presetID: UUID? = nil) {
        self.appState = appState
        self.presetID = presetID
        self.isNewCurve = presetID == nil
        _editingCurve = State(initialValue: curve)
        _presetName = State(initialValue: curve.name)
    }

    private var editingPreset: FanPreset? {
        presetID.flatMap { appState.presetStore.preset(id: $0) }
    }

    private var themeColor: Color {
        guard let editingPreset else { return .orange }
        return PresetTheme.accentColor(for: editingPreset)
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            chart
            controls
            saveRow
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 480)
        .background(PresetTheme.cardBackground(for: editingPreset))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(isNewCurve ? "New Curve" : "Edit Curve")
                    .font(.title2.weight(.semibold))
                Text("Drag points to shape fan response. Double-click chart to add a point.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let temp = appState.monitor.primaryTemperature,
               let fan = appState.monitor.fans.first {
                let rpm = appState.curveEngine.previewRPM(temperature: temp, curve: editingCurve, fan: fan)
                VStack(alignment: .trailing) {
                    Text(TemperatureFormatter.string(temp, unit: appState.settings.temperatureUnit))
                        .font(.headline)
                    Text("Target \(rpm) RPM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(editingCurve.points) { point in
                PointMark(
                    x: .value("Temp", point.temperature),
                    y: .value("Fan %", point.fanPercent)
                )
                .foregroundStyle(selectedPointID == point.id ? themeColor : themeColor.opacity(0.75))
                .symbolSize(selectedPointID == point.id ? 120 : 80)
            }

            ForEach(lineSamples, id: \.temperature) { sample in
                LineMark(
                    x: .value("Temp", sample.temperature),
                    y: .value("Fan %", sample.fanPercent)
                )
                .foregroundStyle(themeColor.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            if let temp = appState.monitor.primaryTemperature {
                RuleMark(x: .value("Current", temp))
                    .foregroundStyle(Color.red.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartXScale(domain: 20...100)
        .chartYScale(domain: 0...100)
        .chartXAxisLabel("Temperature (°C)")
        .chartYAxisLabel("Fan Speed (%)")
        .frame(height: 280)
        .padding(8)
        .background(themeColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    updateNearestPoint(at: value.location, chartSize: CGSize(width: 520, height: 280))
                }
        )
        .onTapGesture(count: 2) {
            addPointNearCenter()
        }
    }

    private var controls: some View {
        HStack {
            Stepper("Hysteresis: \(Int(editingCurve.hysteresisCelsius))°C", value: $editingCurve.hysteresisCelsius, in: 0...5, step: 0.5)
            Spacer()
            Button("Delete Point", role: .destructive) {
                deleteSelectedPoint()
            }
            .disabled(selectedPointID == nil || editingCurve.points.count <= 2)
        }
    }

    private var saveRow: some View {
        HStack {
            TextField("Curve name", text: $presetName)
                .textFieldStyle(.roundedBorder)
            Button("Save") {
                saveProfile()
            }
            .buttonStyle(.borderedProminent)
            .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var lineSamples: [CurvePoint] {
        stride(from: 20.0, through: 100.0, by: 2.0).map { temp in
            CurvePoint(
                temperature: temp,
                fanPercent: CurveEngine.percentForTemperature(temp, curve: editingCurve)
            )
        }
    }

    private func saveProfile() {
        appState.saveCurveProfile(editingCurve, presetID: presetID, name: presetName)
    }

    private func updateNearestPoint(at location: CGPoint, chartSize: CGSize) {
        guard let index = nearestPointIndex(to: location, chartSize: chartSize) else { return }
        selectedPointID = editingCurve.points[index].id

        let temp = 20 + (location.x / chartSize.width) * 80
        let percent = max(0, min(100, 100 - (location.y / chartSize.height) * 100))
        editingCurve.points[index].temperature = min(max(temp, 20), 100)
        editingCurve.points[index].fanPercent = percent
        editingCurve.points.sort { $0.temperature < $1.temperature }
    }

    private func nearestPointIndex(to location: CGPoint, chartSize: CGSize) -> Int? {
        guard !editingCurve.points.isEmpty else { return nil }
        var bestIndex: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for (index, point) in editingCurve.points.enumerated() {
            let x = CGFloat((point.temperature - 20) / 80) * chartSize.width
            let y = (1 - CGFloat(point.fanPercent / 100)) * chartSize.height
            let dx = x - location.x
            let dy = y - location.y
            let distance = hypot(dx, dy)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestDistance < 24 ? bestIndex : nil
    }

    private func addPointNearCenter() {
        let temp = appState.monitor.primaryTemperature ?? 55
        let percent = CurveEngine.percentForTemperature(temp, curve: editingCurve)
        editingCurve.points.append(CurvePoint(temperature: temp, fanPercent: percent))
        editingCurve.points.sort { $0.temperature < $1.temperature }
    }

    private func deleteSelectedPoint() {
        guard let selectedPointID else { return }
        editingCurve.points.removeAll { $0.id == selectedPointID }
        self.selectedPointID = nil
    }
}
