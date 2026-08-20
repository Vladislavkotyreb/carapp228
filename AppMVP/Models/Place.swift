import Foundation
import SwiftData
import SwiftUI

/// Что за место на карте. Три вида — те, за которыми водитель сворачивает с
/// маршрута: где встать, где подкачать и где чиниться.
///
/// `rawValue` уходит в базу, поэтому строки менять нельзя: переименование
/// сотрёт тип у всех уже сохранённых мест.
enum PlaceKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case parking
    case tyre
    case service

    var id: String { rawValue }

    /// Подпись на фильтре
    var plural: String {
        switch self {
        case .parking: "Парковки"
        case .tyre: "Шиномонтаж"
        case .service: "СТО"
        }
    }

    /// Подпись в карточке места
    var singular: String {
        switch self {
        case .parking: "Парковка"
        case .tyre: "Шиномонтаж"
        case .service: "СТО"
        }
    }

    /// Чем это ищется у Яндекса. Слова подобраны под их рубрикатор: «автосервис»
    /// находит и СТО, и автомастерские, а «СТО» само по себе — заправки «СТО»
    /// и мусор из адресов.
    var query: String {
        switch self {
        case .parking: "парковка"
        case .tyre: "шиномонтаж"
        case .service: "автосервис"
        }
    }

    var symbol: String {
        switch self {
        case .parking: "parkingsign"
        case .tyre: "circle.circle"
        case .service: "wrench.and.screwdriver.fill"
        }
    }

    var tint: Color {
        switch self {
        case .parking: Figma.accentsBlue
        case .tyre: Figma.accentsGreen
        case .service: Figma.accentsRed
        }
    }
}

/// Место, которое пользователь добавил сам. Найденные у Яндекса не сохраняются:
/// они живут, пока открыт экран, и подтягиваются заново — иначе база начнёт
/// расходиться с реальностью, а сроки жизни у неё никто не проверяет.
@Model
final class Place {
    var title: String
    /// Строка вместо `PlaceKind`: SwiftData не хранит перечисления напрямую.
    var kindRaw: String
    var latitude: Double
    var longitude: Double
    var note: String?
    var createdAt: Date

    init(title: String,
         kind: PlaceKind,
         latitude: Double,
         longitude: Double,
         note: String? = nil,
         createdAt: Date = .now) {
        self.title = title
        self.kindRaw = kind.rawValue
        self.latitude = latitude
        self.longitude = longitude
        self.note = note
        self.createdAt = createdAt
    }
}

extension Place {
    /// Неизвестный тип не роняет экран: место просто считается СТО. Такое
    /// возможно только если строку в базе поправили руками.
    var kind: PlaceKind {
        get { PlaceKind(rawValue: kindRaw) ?? .service }
        set { kindRaw = newValue.rawValue }
    }
}
