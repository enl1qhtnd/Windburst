import Foundation

public enum MetricChartScale {
    public static let historyWindowSeconds: TimeInterval = 3 * 60
    public static let cpuRange: ClosedRange<Double> = 0...100

    /// Enough slots for one sample per second across the history window.
    public static var historySampleCapacity: Int {
        Int(historyWindowSeconds) + 20
    }

    public static func temperatureRange(unit: TemperatureUnit) -> ClosedRange<Double> {
        unit.convert(0)...unit.convert(100)
    }

    public static func rpmRange(for fan: Fan) -> ClosedRange<Double> {
        0...Double(max(fan.effectiveMaxRPM, 1))
    }
}
