import Foundation

/// Правила рыночной оценки машины: какой VIN пригоден для запроса и когда
/// сохранённая оценка устаревает. Сами запросы живут в `VehicleLookup.swift`,
/// здесь — только решения, которые можно проверить без приложения.
enum MarketPrice {
    /// Оценка ищется по полному VIN: ровно 17 знаков и без маскирующих
    /// звёздочек — замаскированный VIN бесполезен и поставщику.
    static func canEstimate(vin: String?) -> Bool {
        guard let vin else { return false }
        return vin.count == 17 && !vin.contains("*")
    }

    /// Оценка живёт неделю. Цены рынка меняются медленнее, а запрос платный:
    /// чаще обновлять — платить за то же число.
    static let refreshInterval: TimeInterval = 7 * 24 * 3600

    /// Пора ли переспрашивать поставщика. Без даты — пора всегда.
    static func needsRefresh(updatedAt: Date?, now: Date) -> Bool {
        guard let updatedAt else { return true }
        return now.timeIntervalSince(updatedAt) >= refreshInterval
    }
}
