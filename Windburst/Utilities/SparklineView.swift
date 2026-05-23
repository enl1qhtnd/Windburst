import SwiftUI
import Charts
import WindburstShared

struct TemperatureFormatter {
    static func string(_ celsius: Double?, unit: TemperatureUnit, decimals: Int = 0) -> String {
        guard let celsius else { return "—" }
        let value = unit.convert(celsius)
        return String(format: "%.\(decimals)f%@", value, unit.symbol)
    }

    static func color(for celsius: Double?) -> Color {
        guard let celsius else { return .secondary }
        switch celsius {
        case ..<60: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }
}

struct SparklineView: View {
    let samples: [MetricSample]
    var lineColor: Color = .primary
    var height: CGFloat = 14
    var yRange: ClosedRange<Double> = MetricChartScale.cpuRange
    var windowSeconds: TimeInterval = MetricChartScale.historyWindowSeconds

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let end = samples.last?.timestamp ?? Date()
            let start = end.addingTimeInterval(-windowSeconds)
            let ySpan = max(yRange.upperBound - yRange.lowerBound, 0.001)

            var linePath = Path()
            for (index, sample) in samples.enumerated() {
                let x = xPosition(for: sample.timestamp, start: start, width: size.width)
                let y = yPosition(for: sample.value, height: size.height, span: ySpan)
                if index == 0 {
                    linePath.move(to: CGPoint(x: x, y: y))
                } else {
                    linePath.addLine(to: CGPoint(x: x, y: y))
                }
            }

            if samples.count == 1, let sample = samples.first {
                let x = xPosition(for: sample.timestamp, start: start, width: size.width)
                let y = yPosition(for: sample.value, height: size.height, span: ySpan)
                linePath.move(to: CGPoint(x: x, y: y))
                linePath.addLine(to: CGPoint(x: x, y: y))
            }

            context.stroke(linePath, with: .color(lineColor.opacity(0.9)), lineWidth: 1.25)
        }
        .frame(height: height)
        .accessibilityLabel("Sparkline chart")
    }

    private func xPosition(for timestamp: Date, start: Date, width: CGFloat) -> CGFloat {
        let progress = timestamp.timeIntervalSince(start) / windowSeconds
        return width * CGFloat(min(max(progress, 0), 1))
    }

    private func yPosition(for value: Double, height: CGFloat, span: Double) -> CGFloat {
        let normalized = (value - yRange.lowerBound) / span
        let clamped = min(max(normalized, 0), 1)
        return height - (CGFloat(clamped) * height)
    }
}

struct MiniChartView: View {
    let title: String
    let samples: [MetricSample]
    let color: Color
    var yRange: ClosedRange<Double> = MetricChartScale.cpuRange
    var windowSeconds: TimeInterval = MetricChartScale.historyWindowSeconds
    var showYAxis: Bool = false

    private var xDomain: ClosedRange<Date> {
        let end = samples.last?.timestamp ?? Date()
        let start = end.addingTimeInterval(-windowSeconds)
        return start...end
    }

    private var yAxisTickValues: [Double] {
        let lower = yRange.lowerBound
        let upper = yRange.upperBound
        let mid = (lower + upper) / 2
        return [lower, mid, upper]
    }

    private var chartHeight: CGFloat { 56 }

    private var yAxisLabelWidth: CGFloat {
        let maxLength = yAxisTickValues
            .map { yAxisLabel(for: $0).count }
            .max() ?? 2
        return max(22, CGFloat(maxLength) * 7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 4) {
                if showYAxis {
                    yAxisLabels
                        .frame(width: yAxisLabelWidth, height: chartHeight)
                }
                chart
                    .frame(maxWidth: .infinity)
                    .frame(height: chartHeight)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var yAxisLabels: some View {
        GeometryReader { geometry in
            let span = max(yRange.upperBound - yRange.lowerBound, 0.001)
            let inset: CGFloat = 6
            let plotHeight = geometry.size.height
            ZStack(alignment: .topLeading) {
                ForEach(yAxisTickValues, id: \.self) { value in
                    let normalized = (value - yRange.lowerBound) / span
                    let rawY = plotHeight - (CGFloat(normalized) * plotHeight)
                    let y = inset + (rawY / plotHeight) * (plotHeight - (2 * inset))
                    Text(yAxisLabel(for: value))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .frame(width: geometry.size.width, alignment: .trailing)
                        .position(x: geometry.size.width / 2, y: y)
                }
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        Chart {
            if showYAxis {
                ForEach(yAxisTickValues, id: \.self) { tick in
                    RuleMark(y: .value("Grid", tick))
                        .foregroundStyle(.quaternary.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 0.5))
                }
            }

            ForEach(samples) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Value", sample.value)
                )
                .foregroundStyle(color)
                .interpolationMethod(.linear)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yRange)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    private func yAxisLabel(for value: Double) -> String {
        String(format: "%.0f", value)
    }
}
