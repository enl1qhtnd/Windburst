import Foundation
import WindburstShared

@MainActor
final class LiquidctlCurveLoop {
    static let shared = LiquidctlCurveLoop()

    private struct ActiveCurve {
        var config: CurveConfiguration
        var fanByIndex: [Int: Fan]
        var hysteresis = FanCurveInterpolator()
        var lastAppliedPercent: [Int: Int] = [:]
        var lastChangeDate: [Int: Date] = [:]
    }

    private var activeCurves: [UUID: ActiveCurve] = [:]
    private var overriddenFanIndices: Set<Int> = []
    private var timer: Timer?
    private let liquidctlClient = LiquidctlClient.shared
    private var temperatureReader: ((String) -> Double?)?

    private init() {}

    var activeTargets: [Int: Int] {
        var result: [Int: Int] = [:]
        for curve in activeCurves.values {
            for (index, percent) in curve.lastAppliedPercent {
                guard let fan = curve.fanByIndex[index] else { continue }
                let range = fan.effectiveMaxRPM - fan.effectiveMinRPM
                let rpm = fan.effectiveMinRPM + Int(round((Double(percent) / 100.0) * Double(range)))
                result[index] = rpm
            }
        }
        return result
    }

    func configureTemperatureReader(_ reader: @escaping (String) -> Double?) {
        temperatureReader = reader
    }

    func start(config: CurveConfiguration, fans: [Fan]) throws {
        let fanIndices = config.fanIndices.filter { !overriddenFanIndices.contains($0) }
        guard !fanIndices.isEmpty else { return }

        var fanByIndex: [Int: Fan] = [:]
        for fanIndex in fanIndices {
            guard let fan = fans.first(where: { $0.index == fanIndex && $0.liquidctl != nil }) else {
                throw LiquidctlError.invalidOutput("Fan \(fanIndex) is not a liquidctl device")
            }
            fanByIndex[fanIndex] = fan
        }

        var filteredConfig = config
        filteredConfig.fanIndices = fanIndices

        activeCurves[filteredConfig.curve.id] = ActiveCurve(config: filteredConfig, fanByIndex: fanByIndex)
        startTimerIfNeeded()
        Task { await evaluate() }
    }

    func setFanOverridden(_ fanIndex: Int, overridden: Bool) {
        if overridden {
            overriddenFanIndices.insert(fanIndex)
        } else {
            overriddenFanIndices.remove(fanIndex)
        }
    }

    func stop(fanIndex: Int) {
        for (id, var curve) in activeCurves {
            curve.config.fanIndices.removeAll { $0 == fanIndex }
            curve.lastAppliedPercent.removeValue(forKey: fanIndex)
            curve.lastChangeDate.removeValue(forKey: fanIndex)
            curve.fanByIndex.removeValue(forKey: fanIndex)
            if curve.config.fanIndices.isEmpty {
                activeCurves.removeValue(forKey: id)
            } else {
                activeCurves[id] = curve
            }
        }

        if activeCurves.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    func stopAll() {
        activeCurves.removeAll()
        timer?.invalidate()
        timer = nil
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.evaluate()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func evaluate() async {
        guard !activeCurves.isEmpty else { return }

        for id in Array(activeCurves.keys) {
            guard var active = activeCurves[id] else { continue }
            let config = active.config
            guard let temperature = temperatureReader?(config.sensorKey) else { continue }

            for fanIndex in Array(config.fanIndices) {
                guard !overriddenFanIndices.contains(fanIndex) else { continue }
                guard let fan = active.fanByIndex[fanIndex] else { continue }

                let targetPercent = Int(active.hysteresis.targetPercent(for: temperature, curve: config.curve).rounded())
                let lastPercent = active.lastAppliedPercent[fanIndex]
                let lastChange = active.lastChangeDate[fanIndex] ?? .distantPast
                let holdElapsed = Date().timeIntervalSince(lastChange)

                let shouldApply: Bool
                if lastPercent == targetPercent && holdElapsed < config.minimumHoldSeconds {
                    shouldApply = false
                } else if let lastPercent, abs(lastPercent - targetPercent) < 2, holdElapsed < config.minimumHoldSeconds {
                    shouldApply = false
                } else {
                    shouldApply = true
                }

                guard shouldApply else { continue }

                do {
                    try await liquidctlClient.setSpeedPercent(for: fan, percent: Double(targetPercent))
                    guard var latest = activeCurves[id],
                          latest.config.fanIndices.contains(fanIndex),
                          !overriddenFanIndices.contains(fanIndex) else {
                        continue
                    }
                    latest.lastAppliedPercent[fanIndex] = targetPercent
                    latest.lastChangeDate[fanIndex] = Date()
                    latest.hysteresis = active.hysteresis
                    activeCurves[id] = latest
                    active = latest
                } catch {
                    liquidctlClient.reportError(error.localizedDescription)
                }
            }

            if var latest = activeCurves[id] {
                latest.hysteresis = active.hysteresis
                activeCurves[id] = latest
            }
        }
    }
}
