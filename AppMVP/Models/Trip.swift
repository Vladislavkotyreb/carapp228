import Foundation
import SwiftData

/// Одна поездка, посчитанная автопробегом.
///
/// Итог — когда ехали и сколько метров — и линия маршрута для карты на
/// экране поездки. Маршрут лежит только на телефоне (152-ФЗ): это такие
/// же данные о человеке, как госномер. С включённой синхронизацией на
/// сервер в РФ уходят только время, метры и машина (`TripSync`).
@Model
final class Trip {
    var startedAt: Date
    var endedAt: Date
    var meters: Double
    var car: Car?
    /// Маршрут в записи `TripTrack.encode`. Пустой у поездок, записанных до
    /// 08.10.2026, и у оборванных — карта для них не рисуется.
    @Attribute(.externalStorage) var track: Data?
    /// Адреса начала и конца: «улица Остоженка, 12». Их отдаёт геокодер
    /// Яндекса по двум точкам маршрута (решение пользователя 08.10.2026).
    /// Пустые, пока не запрошены или запрос не удался.
    var startAddress: String?
    var endAddress: String?
    /// Записал сам Beepy (автопробег), а не кнопка или команда. Пусто у
    /// поездок до 12.10.2026.
    var auto: Bool?
    /// Имя поездки на сервере синхронизации (`TripSync`). Маршрут и адреса
    /// туда не уходят — только время, метры и машина.
    var syncID: UUID?

    init(startedAt: Date, endedAt: Date, meters: Double, car: Car?, track: Data? = nil) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.meters = meters
        self.car = car
        self.track = track
    }
}

extension Trip {
    /// Имя кадра карты этой поездки в кэше (`TripSnapshots`). Из времени
    /// начала, а не из идентификатора модели: тот между запусками меняет хэш.
    var snapshotKey: String {
        "\(Int((startedAt.timeIntervalSinceReferenceDate * 1000).rounded()))"
    }
}
