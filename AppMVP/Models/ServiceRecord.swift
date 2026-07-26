import Foundation
import SwiftData

/// Запись о техобслуживании. Раньше жила структурой в `CarMainView` с датой
/// строкой — теперь дата хранится как `Date`, а форматируется при отрисовке.
@Model
final class ServiceRecord {
    var date: Date
    /// Пробег на момент ТО, км.
    var mileage: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ServiceWorkItem.record)
    var works: [ServiceWorkItem]

    /// Чеки и фото документов, приложенные к ТО.
    @Attribute(.externalStorage) var receipts: [Data]

    var car: Car?

    init(date: Date, mileage: Int, receipts: [Data] = [], createdAt: Date = .now) {
        self.date = date
        self.mileage = mileage
        self.receipts = receipts
        self.createdAt = createdAt
        self.works = []
    }
}

extension ServiceRecord {
    /// Сумма по всем работам — её показывает карточка в истории.
    var amount: Int {
        works.reduce(0) { $0 + $1.amount }
    }
}

/// Одна работа внутри ТО: «Замена масла — 12 000 ₽».
@Model
final class ServiceWorkItem {
    var title: String
    var amount: Int
    var record: ServiceRecord?

    init(title: String, amount: Int) {
        self.title = title
        self.amount = amount
    }
}
