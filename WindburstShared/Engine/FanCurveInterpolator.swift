import Foundation

public struct FanCurveInterpolator: Sendable {
    public var hysteresisCelsius: Double
    private var lastAppliedPercent: Double?
    private var lastAppliedTemperature: Double?

    public init(hysteresisCelsius: Double = 2.0) {
        self.hysteresisCelsius = hysteresisCelsius
    }

    public mutating func reset() {
        lastAppliedPercent = nil
        lastAppliedTemperature = nil
    }

    public func interpolatePercent(for temperature: Double, curve: FanCurve) -> Double {
        let points = curve.points.sorted { $0.temperature < $1.temperature }
        guard let first = points.first, let last = points.last else { return 0 }

        if temperature <= first.temperature {
            return first.fanPercent
        }
        if temperature >= last.temperature {
            return last.fanPercent
        }

        for index in 0..<(points.count - 1) {
            let left = points[index]
            let right = points[index + 1]
            if temperature >= left.temperature && temperature <= right.temperature {
                let span = right.temperature - left.temperature
                guard span > 0 else { return left.fanPercent }
                let ratio = (temperature - left.temperature) / span
                return left.fanPercent + ratio * (right.fanPercent - left.fanPercent)
            }
        }

        return last.fanPercent
    }

    public mutating func targetPercent(for temperature: Double, curve: FanCurve) -> Double {
        let raw = interpolatePercent(for: temperature, curve: curve)

        if let lastTemp = lastAppliedTemperature,
           let lastPercent = lastAppliedPercent,
           abs(temperature - lastTemp) <= hysteresisCelsius {
            return lastPercent
        }

        lastAppliedTemperature = temperature
        lastAppliedPercent = raw
        return raw
    }

    public func targetRPM(
        for temperature: Double,
        curve: FanCurve,
        minRPM: Int,
        maxRPM: Int,
        hysteresisState: inout FanCurveInterpolator
    ) -> Int {
        let percent = hysteresisState.targetPercent(for: temperature, curve: curve)
        let range = Double(maxRPM - minRPM)
        let rpm = Double(minRPM) + (percent / 100.0) * range
        return Int(rpm.rounded())
    }
}

public enum CurveEngine {
    public static func rpmForTemperature(
        _ temperature: Double,
        curve: FanCurve,
        minRPM: Int,
        maxRPM: Int,
        hysteresisState: inout FanCurveInterpolator
    ) -> Int {
        let percent = hysteresisState.targetPercent(for: temperature, curve: curve)
        let range = Double(max(maxRPM - minRPM, 1))
        let rpm = Double(minRPM) + (percent / 100.0) * range
        return min(max(Int(rpm.rounded()), minRPM), maxRPM)
    }

    public static func percentForTemperature(_ temperature: Double, curve: FanCurve) -> Double {
        var state = FanCurveInterpolator(hysteresisCelsius: 0)
        return state.interpolatePercent(for: temperature, curve: curve)
    }
}
