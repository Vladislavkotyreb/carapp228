import Foundation

/// Арифметика обслуживания: когда следующее ТО и сколько уже потрачено.
///
/// Работает со значениями, а не с `Car`: модель SwiftData сюда не заходит
/// намеренно — этот слой должен собираться и проверяться без приложения,
/// см. `tools/run-pure-checks.sh`. Вызывающий передаёт пробеги записей.
enum ServiceMath {
    /// Межсервисный интервал: следующее ТО через 10 000 км от последнего.
    static let interval = 10_000

    /// Пробег на последнем ТО — от него отсчитывается интервал.
    ///
    /// Записей нет — берётся текущий одометр: у машины без истории «ТО через»
    /// показывает полный интервал, а не путь, пройденный с завода.
    static func lastServiceMileage(odometer: Int, serviceMileages: [Int]) -> Int {
        serviceMileages.max() ?? odometer
    }

    /// «ТО через N км» — остаток до следующего сервиса.
    ///
    /// Не бывает отрицательным: просроченное ТО показывает 0, а не долг.
    static func kmUntilService(odometer: Int, serviceMileages: [Int]) -> Int {
        let last = lastServiceMileage(odometer: odometer, serviceMileages: serviceMileages)
        return max(0, last + interval - odometer)
    }

    /// Доля интервала, которую уже проехали: 0…1 для полосы прогресса.
    ///
    /// Одометр меньше пробега на последнем ТО — данные разъехались; отдаём 0,
    /// а не отрицательную ширину полосы.
    static func progress(odometer: Int, serviceMileages: [Int]) -> Double {
        let last = lastServiceMileage(odometer: odometer, serviceMileages: serviceMileages)
        let driven = Double(odometer - last)
        return min(1, max(0, driven / Double(interval)))
    }

    /// «Всего потрачено» — сумма по всем работам всех ТО.
    static func totalSpent(amounts: [Int]) -> Int {
        amounts.reduce(0, +)
    }

    /// Одометр после сохранения ТО: он не может быть меньше пробега записи.
    static func odometerAfterService(current: Int, serviceMileage: Int) -> Int {
        max(current, serviceMileage)
    }
}
