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

    private static func markKey(for id: String) -> String {
        "service.reminder." + id
    }

    /// Имя машины для напоминаний — по дате добавления, в микросекундах.
    /// `persistentModelID.hashValue` сюда не годится: хэш в Swift свой у
    /// каждого запуска, и одна машина получала новый идентификатор
    /// уведомления при каждом открытии приложения (лог 08.10.2026).
    static func key(createdAt: Date) -> String {
        String(Int(createdAt.timeIntervalSinceReferenceDate * 1_000_000))
    }

    /// Ставит или снимает напоминание. Когда и о чём напоминать, решает
    /// `ServiceMath.reminderStep`; уведомление уходит через минуту
    /// (мгновенное показалось бы системным сбоем, а не напоминанием).
    static func update(id: String, name: String, plate: String, kmLeft: Int) async {
        let center = UNUserNotificationCenter.current()
        let key = identifier(for: id)

        let stage: ServiceMath.ReminderStage
        switch ServiceMath.reminderStep(kmLeft: kmLeft, mark: mark(for: id), now: .now) {
        case .clear:
            forget(id: id)
            return
        case .wait:
            return
        case .send(let next):
            stage = next
        }

        let granted = await authorized(center)
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Пора на ТО"
        content.body = ServiceMath.reminderText(name: name, plate: plate,
                                                kmLeft: kmLeft)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60,
                                                        repeats: false)
        // Идентификатор тот же, что у прошлого: висящее в очереди и уже
        // показанное заменяются, а не копятся.
        do {
            try await center.add(UNNotificationRequest(identifier: key,
                                                       content: content,
                                                       trigger: trigger))
            setMark(.init(stage: stage, sentAt: .now), for: id)
        } catch {
            // Не поставилось — отметки нет, следующий расчёт попробует снова.
        }
    }

    /// Машину удалили или зона перестала быть красной: напоминание из
    /// очереди уходит, отметка — тоже.
    static func forget(id: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(for: id)])
        setMark(nil, for: id)
    }

    private static func mark(for id: String) -> ServiceMath.ReminderMark? {
        guard let data = UserDefaults.standard.data(forKey: markKey(for: id)) else { return nil }
        return try? JSONDecoder().decode(ServiceMath.ReminderMark.self, from: data)
    }

    private static func setMark(_ mark: ServiceMath.ReminderMark?, for id: String) {
        let key = markKey(for: id)
        guard let mark, let data = try? JSONEncoder().encode(mark) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(data, forKey: key)
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
