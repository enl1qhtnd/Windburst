import Foundation
import WindburstShared

@MainActor
final class HelperClient: NSObject {
    static let shared = HelperClient()

    private var connection: NSXPCConnection?
    private(set) var isConnected = false
    private(set) var registrationStatus: HelperRegistrationStatus = .notRegistered
    var lastError: String?

    var isRegistered: Bool { registrationStatus.isOperational }

    private override init() {
        super.init()
    }

    func refreshRegistrationStatus() {
        registrationStatus = HelperRegistration.currentStatus()
    }

    func registerHelperIfNeeded() async {
        lastError = nil
        registrationStatus = await HelperRegistration.register()

        if case .failed(let message) = registrationStatus {
            lastError = message
        } else if case .requiresApproval = registrationStatus {
            lastError = registrationStatus.userFacingDescription
            SystemSettingsOpener.openBackgroundItems()
        }

        if registrationStatus.isOperational {
            connect()
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !isConnected {
                connect()
            }
        } else {
            isConnected = false
        }
    }

    func connect() {
        disconnect()

        let conn = NSXPCConnection(machServiceName: WindburstXPCConstants.machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: WindburstHelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.isConnected = false
            }
        }
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.isConnected = false
            }
        }
        conn.resume()
        connection = conn

        Task {
            let ok = await ping()
            isConnected = ok
            if !ok, registrationStatus.isOperational {
                lastError = "Helper is registered but not responding to XPC."
            }
        }
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
        isConnected = false
    }

    func shutdown() async {
        guard let proxy = helperProxy else { return }
        await withCheckedContinuation { continuation in
            proxy.shutdown { _ in
                continuation.resume()
            }
        }
        disconnect()
    }

    private var helperProxy: WindburstHelperProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in
                self?.lastError = error.localizedDescription
                self?.isConnected = false
            }
        } as? WindburstHelperProtocol
    }

    func ping() async -> Bool {
        guard let proxy = helperProxy else { return false }
        return await withCheckedContinuation { continuation in
            proxy.ping { ok in
                continuation.resume(returning: ok)
            }
        }
    }

    func discoverFans() async -> [Fan] {
        guard let proxy = helperProxy else { return [] }
        return await withCheckedContinuation { continuation in
            proxy.discoverFans { data in
                continuation.resume(returning: XPCCodec.decode([Fan].self, from: data) ?? [])
            }
        }
    }

    func discoverSensors() async -> [Sensor] {
        guard let proxy = helperProxy else { return [] }
        return await withCheckedContinuation { continuation in
            proxy.discoverSensors { data in
                continuation.resume(returning: XPCCodec.decode([Sensor].self, from: data) ?? [])
            }
        }
    }

    func readAllKeys() async -> [String: String] {
        guard let proxy = helperProxy else { return [:] }
        return await withCheckedContinuation { continuation in
            proxy.readAllKeys { data in
                continuation.resume(returning: XPCCodec.decode([String: String].self, from: data) ?? [:])
            }
        }
    }

    func setManualMode(fanIndex: Int) async -> Bool {
        guard let proxy = helperProxy else { return false }
        return await withCheckedContinuation { continuation in
            proxy.setManualMode(fanIndex: fanIndex) { ok, _ in
                continuation.resume(returning: ok)
            }
        }
    }

    func setAutoMode(fanIndex: Int) async -> Bool {
        guard let proxy = helperProxy else { return false }
        return await withCheckedContinuation { continuation in
            proxy.setAutoMode(fanIndex: fanIndex) { ok, _ in
                continuation.resume(returning: ok)
            }
        }
    }

    func setTargetRPM(fanIndex: Int, rpm: Int) async -> Bool {
        guard let proxy = helperProxy else { return false }
        return await withCheckedContinuation { continuation in
            proxy.setTargetRPM(fanIndex: fanIndex, rpm: rpm) { ok, _ in
                continuation.resume(returning: ok)
            }
        }
    }

    func startCurve(_ config: CurveConfiguration) async -> Bool {
        guard let proxy = helperProxy else { return false }
        let data = XPCCodec.encode(config)
        return await withCheckedContinuation { continuation in
            proxy.startCurve(data) { ok, _ in
                continuation.resume(returning: ok)
            }
        }
    }

    func stopCurve(fanIndex: Int) async -> Bool {
        guard let proxy = helperProxy else { return false }
        return await withCheckedContinuation { continuation in
            proxy.stopCurve(fanIndex: fanIndex) { ok, _ in
                continuation.resume(returning: ok)
            }
        }
    }

    func stopAllCurves() async -> Bool {
        guard let proxy = helperProxy else { return false }
        return await withCheckedContinuation { continuation in
            proxy.stopAllCurves { ok in
                continuation.resume(returning: ok)
            }
        }
    }

    func getActiveCurveStatus() async -> [Int: Int] {
        guard let proxy = helperProxy else { return [:] }
        return await withCheckedContinuation { continuation in
            proxy.getActiveCurveStatus { data in
                let status = XPCCodec.decode(ActiveCurveStatus.self, from: data)
                continuation.resume(returning: status?.targets ?? [:])
            }
        }
    }
}
