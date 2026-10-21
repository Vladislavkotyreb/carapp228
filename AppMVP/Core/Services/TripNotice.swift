import UserNotifications

/// Уведомление «Поездка началась» (просьба пользователя 18.10.2026): человек
/// видит, что Beepy поездку заметил, — особенно когда её начал Bluetooth
/// машины, а телефон в кармане. Тексты — `TripLink.startNotice`.
enum TripNotice {
    /// Спросить разрешение. Только с экрана — когда включают автопробег или
    /// привязывают Bluetooth: из фона системный вопрос не показывается, и
    /// первое уведомление пропало бы молча.
    static func requestPermission() {
        Task {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    static func started(_ cause: TripLink.StartCause) {
        let text = TripLink.startNotice(cause)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        // Одно на поездку: новое заменяет прошлое, а не копится в центре.
        let request = UNNotificationRequest(identifier: "trip.started", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Баннеры и при открытом приложении. Без делегата система молча глотает
/// уведомление на переднем плане — а в машине Beepy как раз бывает открыт.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
