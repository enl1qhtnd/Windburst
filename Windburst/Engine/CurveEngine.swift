import Foundation
import WindburstShared

@MainActor
final class CurveEngineService {
    static let shared = CurveEngineService()

    private let helperClient = HelperClient.shared
    private let liquidctlClient = LiquidctlClient.shared
    private let liquidctlCurveLoop = LiquidctlCurveLoop.shared

    func applyPreset(
        _ preset: FanPreset,
        fans: [Fan],
        sensorKey: String,
        linkFans: Bool,
        backend: FanControlBackend
    ) async throws {
        let indices = linkFans ? fans.map(\.index) : preset.linkedFanIndices
        let fanIndices = indices.isEmpty ? fans.map(\.index) : indices

        var minMap: [Int: Int] = [:]
        var maxMap: [Int: Int] = [:]
        for fan in fans where fanIndices.contains(fan.index) {
            minMap[fan.index] = fan.effectiveMinRPM
            maxMap[fan.index] = fan.effectiveMaxRPM
        }

        var curve = preset.curve
        curve.sensorKey = sensorKey

        let config = CurveConfiguration(
            curve: curve,
            fanIndices: fanIndices,
            sensorKey: sensorKey,
            fanMinRPM: minMap,
            fanMaxRPM: maxMap
        )

        switch backend {
        case .smc:
            let success = await helperClient.startCurve(config)
            if !success {
                throw NSError(domain: "Windburst", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to start curve"])
            }
        case .liquidctl:
            try liquidctlCurveLoop.start(config: config, fans: fans)
        }
    }

    func stopCurve(for fanIndex: Int, backend: FanControlBackend) async {
        switch backend {
        case .smc:
            _ = await helperClient.stopCurve(fanIndex: fanIndex)
        case .liquidctl:
            liquidctlCurveLoop.stop(fanIndex: fanIndex)
        }
    }

    func returnAllToAuto(backend: FanControlBackend) async {
        switch backend {
        case .smc:
            _ = await helperClient.stopAllCurves()
        case .liquidctl:
            liquidctlCurveLoop.stopAll()
        }
    }

    func setManualRPM(fan: Fan, rpm: Int, backend: FanControlBackend) async throws {
        switch backend {
        case .smc:
            let success = await helperClient.setTargetRPM(fanIndex: fan.index, rpm: rpm)
            if !success {
                throw NSError(domain: "Windburst", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to set RPM"])
            }
        case .liquidctl:
            try await liquidctlClient.setSpeedPercent(for: fan, rpm: rpm)
        }
    }

    func setAutoMode(for fanIndex: Int, backend: FanControlBackend) async {
        switch backend {
        case .smc:
            _ = await helperClient.setAutoMode(fanIndex: fanIndex)
        case .liquidctl:
            liquidctlCurveLoop.stop(fanIndex: fanIndex)
        }
    }

    func setManualMode(for fanIndex: Int, backend: FanControlBackend) async -> Bool {
        switch backend {
        case .smc:
            return await helperClient.setManualMode(fanIndex: fanIndex)
        case .liquidctl:
            liquidctlCurveLoop.stop(fanIndex: fanIndex)
            return liquidctlClient.isAvailable
        }
    }

    func previewRPM(temperature: Double, curve: FanCurve, fan: Fan) -> Int {
        var state = FanCurveInterpolator(hysteresisCelsius: curve.hysteresisCelsius)
        return CurveEngine.rpmForTemperature(
            temperature,
            curve: curve,
            minRPM: fan.effectiveMinRPM,
            maxRPM: fan.effectiveMaxRPM,
            hysteresisState: &state
        )
    }
}
