import Foundation
import WindburstShared

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: WindburstHelperProtocol.self)
        newConnection.exportedObject = HelperService.shared
        newConnection.resume()
        return true
    }
}

final class HelperService: NSObject, WindburstHelperProtocol {
    static let shared = HelperService()

    private let driver = SMCDriver()
    private let fanController = FanController()
    private let curveLoop = CurveLoop()

    private override init() {
        super.init()
        setupSignalHandlers()
        do {
            try driver.open()
        } catch {
            NSLog("WindburstHelper: failed to open SMC: \(error.localizedDescription)")
        }
    }

    private func setupSignalHandlers() {
        signal(SIGTERM) { _ in
            HelperService.shared.teardown()
            exit(0)
        }
        signal(SIGINT) { _ in
            HelperService.shared.teardown()
            exit(0)
        }
    }

    private func teardown() {
        curveLoop.stopAll()
        fanController.restoreAllToAuto(driver: driver)
        driver.close()
    }

    func ping(reply: @escaping (Bool) -> Void) {
        reply(driver.isConnected)
    }

    func discoverFans(reply: @escaping (Data) -> Void) {
        do {
            let fans = try driver.discoverFans()
            reply(XPCCodec.encode(fans))
        } catch {
            reply(XPCCodec.encode([Fan]()))
        }
    }

    func discoverSensors(reply: @escaping (Data) -> Void) {
        do {
            let sensors = try driver.discoverSensors()
            reply(XPCCodec.encode(sensors))
        } catch {
            reply(XPCCodec.encode([Sensor]()))
        }
    }

    func readAllKeys(reply: @escaping (Data) -> Void) {
        do {
            let keys = try driver.enumerateKeys()
            var values: [String: String] = [:]
            for key in keys {
                if let data = try? driver.readRaw(key: key) {
                    values[key] = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                }
            }
            reply(XPCCodec.encode(values))
        } catch {
            reply(XPCCodec.encode([String: String]()))
        }
    }

    func setManualMode(fanIndex: Int, reply: @escaping (Bool, String?) -> Void) {
        do {
            try fanController.setManualMode(fanIndex: fanIndex, driver: driver)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func setAutoMode(fanIndex: Int, reply: @escaping (Bool, String?) -> Void) {
        do {
            try fanController.setAutoMode(fanIndex: fanIndex, driver: driver)
            curveLoop.stop(fanIndex: fanIndex)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func setTargetRPM(fanIndex: Int, rpm: Int, reply: @escaping (Bool, String?) -> Void) {
        do {
            try fanController.setTargetRPM(fanIndex: fanIndex, rpm: rpm, driver: driver)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func startCurve(_ configData: Data, reply: @escaping (Bool, String?) -> Void) {
        guard let config = XPCCodec.decode(CurveConfiguration.self, from: configData) else {
            reply(false, "Invalid curve configuration")
            return
        }
        do {
            try curveLoop.start(config: config, driver: driver, fanController: fanController)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func stopCurve(fanIndex: Int, reply: @escaping (Bool, String?) -> Void) {
        curveLoop.stop(fanIndex: fanIndex)
        do {
            try fanController.setAutoMode(fanIndex: fanIndex, driver: driver)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func stopAllCurves(reply: @escaping (Bool) -> Void) {
        curveLoop.stopAll()
        fanController.restoreAllToAuto(driver: driver)
        reply(true)
    }

    func getActiveCurveStatus(reply: @escaping (Data) -> Void) {
        reply(XPCCodec.encode(ActiveCurveStatus(targets: curveLoop.activeTargets)))
    }

    func shutdown(reply: @escaping (Bool) -> Void) {
        teardown()
        reply(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exit(0)
        }
    }
}
