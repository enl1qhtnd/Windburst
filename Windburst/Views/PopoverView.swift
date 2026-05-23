import SwiftUI
import Charts
import WindburstShared

struct PopoverView: View {
    @ObservedObject var appState: AppState
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            header
            charts
            fanList
            footer
        }
        .padding(16)
        .frame(width: 340)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(TemperatureFormatter.string(appState.monitor.primaryTemperature, unit: appState.settings.temperatureUnit, decimals: 0))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(TemperatureFormatter.color(for: appState.monitor.primaryTemperature))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)

            VStack(alignment: .leading, spacing: 2) {
                Text("CPU \(Int(appState.monitor.cpuUsagePercent))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Up \(formatUptime(appState.monitor.uptime))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)

            Spacer(minLength: 0)

            Button {
                appState.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .padding(.top, 4)
        }
    }

    private var charts: some View {
        HStack(spacing: 8) {
            MiniChartView(
                title: "CPU %",
                samples: appState.monitor.cpuHistory,
                color: .blue,
                yRange: MetricChartScale.cpuRange,
                showYAxis: true
            )
            .frame(maxWidth: .infinity)

            MiniChartView(
                title: "Temp \(appState.settings.temperatureUnit.symbol)",
                samples: convertedTempHistory,
                color: .orange,
                yRange: MetricChartScale.temperatureRange(unit: appState.settings.temperatureUnit),
                showYAxis: true
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var convertedTempHistory: [MetricSample] {
        appState.monitor.temperatureHistory.map {
            MetricSample(timestamp: $0.timestamp, value: appState.settings.temperatureUnit.convert($0.value))
        }
    }

    private var fanList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(visibleFans) { fan in
                    FanDetailView(fan: fan, appState: appState)
                }

                if hiddenFanCount > 0 {
                    Text("\(hiddenFanCount) hidden fan\(hiddenFanCount == 1 ? "" : "s") — manage in Settings → Fans")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxHeight: 220)
    }

    private var visibleFans: [Fan] {
        appState.monitor.fans.filter { !appState.fanPreferencesStore.isHidden($0.index) }
    }

    private var hiddenFanCount: Int {
        appState.monitor.fans.filter { appState.fanPreferencesStore.isHidden($0.index) }.count
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if let statusMessage = appState.fanControlStatusMessage {
                Label(statusMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("New Curve") {
                    appState.openCurveEditor(curve: FanCurve.defaultCurve(name: "New Curve"))
                }

                Spacer()

                Button("Quit") {
                    Task {
                        await appState.quit()
                        onClose()
                    }
                }
                .keyboardShortcut("q")
            }
        }
        .padding(.top, 4)
    }

    private func formatUptime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
