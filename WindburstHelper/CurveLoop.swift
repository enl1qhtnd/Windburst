import Foundation
import WindburstShared

final class CurveLoop {
    private struct ActiveCurve {
        var config: CurveConfiguration
        var hysteresis = FanCurveInterpolator()
        var lastAppliedRPM: [Int: Int] = [:]
        var lastChangeDate: [Int: Date] = [:]
    }

    private var activeCurves: [UUID: ActiveCurve] = [:]
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "de.enl1qhtnd.windburst.curveloop", qos: .userInitiated)
    private let lock = NSLock()

    var activeTargets: [Int: Int] {
        lock.lock()
        defer { lock.unlock() }

        var result: [Int: Int] = [:]
        for curve in activeCurves.values {
            for (index, rpm) in curve.lastAppliedRPM {
                result[index] = rpm
            }
        }
        return result
    }

    func start(config: CurveConfiguration, driver: SMCDriver, fanController: FanController) throws {
        lock.lock()
        activeCurves[config.curve.id] = ActiveCurve(config: config)
        lock.unlock()

        startTimerIfNeeded(driver: driver, fanController: fanController)
        queue.async { [weak self] in
            self?.evaluate(driver: driver, fanController: fanController)
        }
    }

    func stop(fanIndex: Int) {
        lock.lock()
        defer { lock.unlock() }

        for (id, var curve) in activeCurves {
            curve.config.fanIndices.removeAll { $0 == fanIndex }
            curve.lastAppliedRPM.removeValue(forKey: fanIndex)
            curve.lastChangeDate.removeValue(forKey: fanIndex)
            if curve.config.fanIndices.isEmpty {
                activeCurves.removeValue(forKey: id)
            } else {
                activeCurves[id] = curve
            }
        }

        if activeCurves.isEmpty {
            timer?.cancel()
            timer = nil
        }
    }

    func stopAll() {
        lock.lock()
        defer { lock.unlock() }
        activeCurves.removeAll()
        timer?.cancel()
        timer = nil
    }

    private func startTimerIfNeeded(driver: SMCDriver, fanController: FanController) {
        guard timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.evaluate(driver: driver, fanController: fanController)
        }
        timer.resume()
        self.timer = timer
    }

    private func evaluate(driver: SMCDriver, fanController: FanController) {
        lock.lock()
        let curves = activeCurves
        lock.unlock()

        guard !curves.isEmpty else { return }

        for (id, var active) in curves {
            let config = active.config

            guard let temperature = try? driver.readTemperature(key: config.sensorKey) else {
                continue
            }

            for fanIndex in config.fanIndices {
                let minRPM = config.fanMinRPM[fanIndex] ?? 800
                let maxRPM = config.fanMaxRPM[fanIndex] ?? 6000
                let targetRPM = CurveEngine.rpmForTemperature(
                    temperature,
                    curve: config.curve,
                    minRPM: minRPM,
                    maxRPM: maxRPM,
                    hysteresisState: &active.hysteresis
                )

                let lastRPM = active.lastAppliedRPM[fanIndex]
                let lastChange = active.lastChangeDate[fanIndex] ?? .distantPast
                let holdElapsed = Date().timeIntervalSince(lastChange)

                if lastRPM == targetRPM && holdElapsed < config.minimumHoldSeconds {
                    continue
                }

                if let lastRPM, abs(lastRPM - targetRPM) < 50, holdElapsed < config.minimumHoldSeconds {
                    continue
                }

                do {
                    try fanController.setTargetRPM(fanIndex: fanIndex, rpm: targetRPM, driver: driver)
                    active.lastAppliedRPM[fanIndex] = targetRPM
                    active.lastChangeDate[fanIndex] = Date()
                } catch {
                    NSLog("WindburstHelper curve error: \(error.localizedDescription)")
                }
            }

            lock.lock()
            activeCurves[id] = active
            lock.unlock()
        }
    }
}
