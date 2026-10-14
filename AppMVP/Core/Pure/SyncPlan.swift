import Foundation

/// Синхронизация поездок с сервером (решение пользователя 12.10.2026):
/// что отправить и что сервер должен удалить.
///
/// Правок по всему приложению не отслеживаем — пробег меняют десяток экранов.
/// Вместо этого у каждой отправленной записи запоминается отпечаток её полей.
/// Отпечаток другой — запись изменилась и уходит снова; записи нет, а
/// отпечаток помнится — её удалили, и серверу уходит удаление.
///
/// На сервер уходит только это: у машины — название и пробег, у поездки —
/// время, метры и машина. Госномер, VIN и маршрут остаются на телефоне.
/// Конфликты решает сервер (`server/src/sync.ts`): новее побеждает, удаление
/// окончательно. Что он вернул — уже итог, и телефон берёт его как есть.
enum SyncPlan {
    struct Car: Equatable {
        var id: UUID
        var name: String
        var odometer: Int
        var trackedKm: Int
    }

    struct Trip: Equatable {
        var id: UUID
        var carID: UUID?
        var startedAt: Date
        var endedAt: Date
        var meters: Double
        var auto: Bool
    }

    /// Сколько записей уходит за один запрос: сервер больше не примет.
    static let tripsPerRequest = 500
    static let carsPerRequest = 100

    /// Время — до миллисекунды: дробные секунды сервер отдаёт округлёнными,
    /// и без этого вернувшаяся поездка казалась бы изменённой.
    private static func ms(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSinceReferenceDate * 1000).rounded())
    }

    static func fingerprint(_ car: Car) -> String {
        "\(car.name)|\(car.odometer)|\(car.trackedKm)"
    }

    static func fingerprint(_ trip: Trip) -> String {
        "\(trip.carID?.uuidString ?? "-")|\(ms(trip.startedAt))|\(ms(trip.endedAt))|\((trip.meters * 10).rounded() / 10)|\(trip.auto)"
    }

    /// Что отправить: изменённое и новое — целиком, пропавшее — удалением.
    static func outgoing<T>(_ local: [T], synced: [UUID: String],
                            id: (T) -> UUID, print: (T) -> String) -> (changed: [T], deleted: [UUID]) {
        let changed = local.filter { synced[id($0)] != print($0) }
        let present = Set(local.map(id))
        let deleted = synced.keys.filter { !present.contains($0) }.sorted { $0.uuidString < $1.uuidString }
        return (changed, deleted)
    }

    /// Курсор сервера — строка из цифр; всё прочее значит «с начала».
    static func validCursor(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.count <= 15, value.allSatisfy(\.isASCIIDigit) else { return nil }
        return value
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
