import Foundation

/// Данные машины, полученные по госномеру.
/// VIN и поколение опциональны: не каждый поставщик их отдаёт, а некоторые
/// присылают VIN замаскированным звёздочками — такое значение бесполезно.
struct FoundVehicle: Equatable {
    let name: String
    var vin: String?
    var generation: String?
    var odometer: Int?

    /// Замаскированный VIN считаем отсутствующим.
    var displayVIN: String? {
        guard let vin, !vin.isEmpty, !vin.contains("*") else { return nil }
        return vin
    }
}

enum VehicleLookupError: Error {
    /// Номера нет в базе — состояние из макета «Мы не нашли такого номера».
    case notFound
    /// Сеть или поставщик недоступны.
    case unavailable
}

/// Поиск машины по госномеру.
///
/// Реализации поверх реального API появятся, когда будет свой сервер: ключ
/// поставщика нельзя держать в приложении — он вынимается из `.ipa`, и за него
/// спишут баланс платного API. Запрос пойдёт через свой эндпоинт,
/// см. docs/BACKEND.md.
protocol VehicleLookup: Sendable {
    func lookup(plate: String) async throws -> FoundVehicle
}

/// Заглушка до подключения поставщика: любой корректный номер находит машину
/// с данными из макета (node 45854:2936).
struct StubVehicleLookup: VehicleLookup {
    func lookup(plate: String) async throws -> FoundVehicle {
        guard PlateFormat.isValid(plate) else { throw VehicleLookupError.notFound }
        return FoundVehicle(
            name: "Mercedes-Benz GL-класс",
            vin: "423423432FRFRIFR",
            generation: "X166 (2015-2026)",
            odometer: 9_000_000
        )
    }
}
