import Foundation
import SwiftData

/// Машина пользователя. Хранится локально на устройстве — по 152-ФЗ данные
/// (госномер, VIN) не покидают телефон, пока не появится сервер в РФ.
@Model
final class Car {
    /// Госномер в формате «В 777 ОР 777», нормализованный `PlateFormat`.
    var plate: String
    var name: String
    var vin: String?
    var generation: String?
    /// Текущий пробег в км.
    var odometer: Int
    /// Цена машины в рублях, введённая пользователем. Необязательная, и это
    /// не небрежность: у машин, добавленных до появления поля, её нет вовсе,
    /// а облегчённая миграция SwiftData добавляет молча только то, что может
    /// оставить пустым. Пустая цена честнее выдуманной.
    var price: Int?
    /// Средняя рыночная цена по объявлениям — оценка AvtoVinCod по VIN.
    /// Показывается, пока пользователь не ввёл свою; обновляется по правилу
    /// `MarketPrice.needsRefresh`. Поля пустые у машин без полного VIN.
    var marketPrice: Int?
    var marketPriceDate: Date?
    /// По скольким объявлениям посчитана средняя — для объяснения в шторке.
    var marketOffers: Int?
    /// Фото машины. Крупные блобы SwiftData держит отдельным файлом, а не в базе.
    @Attribute(.externalStorage) var photo: Data?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ServiceRecord.car)
    var services: [ServiceRecord]

    init(
        plate: String,
        name: String,
        vin: String? = nil,
        generation: String? = nil,
        odometer: Int,
        price: Int? = nil,
        photo: Data? = nil,
        createdAt: Date = .now
    ) {
        self.plate = plate
        self.name = name
        self.vin = vin
        self.generation = generation
        self.odometer = odometer
        self.price = price
        self.photo = photo
        self.createdAt = createdAt
        self.services = []
    }
}

extension Car {
    /// История ТО от свежих к старым — в этом порядке карточки идут в макете.
    var sortedServices: [ServiceRecord] {
        services.sorted { $0.date > $1.date }
    }
}
