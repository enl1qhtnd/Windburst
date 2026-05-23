import Foundation
import WindburstShared

final class FanController {
    private var controlledFanIndices = Set<Int>()

    func setManualMode(fanIndex: Int, driver: SMCDriver) throws {
        try driver.setFanManualMode(index: fanIndex)
        controlledFanIndices.insert(fanIndex)
    }

    func setAutoMode(fanIndex: Int, driver: SMCDriver) throws {
        try driver.setFanAutoMode(index: fanIndex)
        controlledFanIndices.remove(fanIndex)
    }

    func setTargetRPM(fanIndex: Int, rpm: Int, driver: SMCDriver) throws {
        let fans = try driver.discoverFans()
        guard let fan = fans.first(where: { $0.index == fanIndex }) else {
            throw SMCError.keyNotFound("Fan \(fanIndex)")
        }
        try driver.setFanTargetRPM(
            index: fanIndex,
            rpm: rpm,
            minRPM: fan.effectiveMinRPM,
            maxRPM: fan.effectiveMaxRPM
        )
        controlledFanIndices.insert(fanIndex)
    }

    func restoreAllToAuto(driver: SMCDriver) {
        if controlledFanIndices.isEmpty {
            if let fans = try? driver.discoverFans() {
                driver.restoreAllFansToAuto(fans: fans)
            }
            return
        }

        for index in controlledFanIndices {
            try? driver.setFanAutoMode(index: index)
        }
        controlledFanIndices.removeAll()

        if let fans = try? driver.discoverFans() {
            driver.restoreAllFansToAuto(fans: fans)
        }
    }
}
