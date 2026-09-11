import Foundation
import UserNotifications

/// Напоминание «пора на ТО» — локальное уведомление на устройстве.
///
/// Локальное, а не push: push требует платного Apple Developer Program, а
/// напоминание считается по данным, которые и так лежат на телефоне.
/// Разрешение спрашивается один раз при первом попадании машины в красную
/// зону — до этого повода тревожить человека нет.
enum ServiceReminder {
    /// Одно уведомление на машину: новый расчёт заменяет прошлый.
    private static func identifier(for id: String) -> String {
        "service-due-" + id
    }

    /// Ставит или снимает напоминание. `kmLeft` меньше порога — уведомление
    /// уходит через минуту (мгновенное показалось бы системным сбоем, а не
    /// напоминанием); иначе прошлое снимается.
    static func update(id: String, name: String, plate: String, kmLeft: Int) async {
        let center = UNUserNotificationCenter.current()
        let key = identifier(for: id)

        guard ServiceMath.urgency(kmLeft: kmLeft) == .urgent else {
            center.removePendingNotificationRequests(withIdentifiers: [key])
            return
        }

        let granted = await authorized(center)
        guard granted else { return }

        // Пока предыдущее напоминание про эту же машину висит в очереди,
        // второе не заводим: иначе каждый пересчёт плодил бы дубли.
        let pending = await center.pendingNotificationRequests()
        guard !pending.contains(where: { $0.identifier == key }) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Пора на ТО"
        content.body = ServiceMath.reminderText(name: name, plate: plate,
                                                kmLeft: kmLeft)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60,
                                                        repeats: false)
        try? await center.add(UNNotificationRequest(identifier: key,
                                                    content: content,
                                                    trigger: trigger))
    }

    private static func authorized(_ center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }
}
