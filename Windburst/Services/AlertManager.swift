import Foundation
import UserNotifications
import WindburstShared

@MainActor
final class AlertManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertManager()

    private var lastAlertDate: Date?
    private var lastAlertTemperature: Double?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func checkTemperature(_ temperature: Double?, settings: AppSettings) {
        guard settings.highTempAlertEnabled,
              let temperature,
              temperature >= settings.highTempThreshold else {
            return
        }

        if let lastTemp = lastAlertTemperature,
           let lastDate = lastAlertDate,
           abs(lastTemp - temperature) < 1,
           Date().timeIntervalSince(lastDate) < 120 {
            return
        }

        lastAlertTemperature = temperature
        lastAlertDate = Date()

        let content = UNMutableNotificationContent()
        content.title = "Windburst High Temperature"
        content.body = String(format: "Sensor reached %.0f°C (threshold %.0f°C)", temperature, settings.highTempThreshold)
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
