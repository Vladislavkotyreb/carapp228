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
    /// И не бывает больше интервала: запись ТО на пробеге выше одометра
    /// (одометр поправили вниз руками) давала «ТО через 99 799 999 км»
    /// (найдено 14.10.2026). Такие данные читаются как «только что из
    /// сервиса» — так же их понимает полоса в `progress`.
    static func kmUntilService(odometer: Int, serviceMileages: [Int]) -> Int {
        let last = lastServiceMileage(odometer: odometer, serviceMileages: serviceMileages)
        return min(interval, max(0, last + interval - odometer))
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

    /// Светофор срочности ТО. Пороги — просьба пользователя: жёлтый за
    /// 5 000 км, красный за 1 000. Значения именно такие, потому что
    /// интервал 10 000: жёлтый — половина пути, красный — последняя
    /// десятая, когда пора записываться.
    enum Urgency: String, CaseIterable {
        /// Ехать спокойно.
        case normal
        /// Осталось 5 000 км и меньше — пора планировать.
        case soon
        /// Меньше 1 000 км или уже просрочено — пора ехать.
        case urgent
    }

    static let soonThreshold = 5_000
    static let urgentThreshold = 1_000

    static func urgency(kmLeft: Int) -> Urgency {
        if kmLeft < urgentThreshold { return .urgent }
        if kmLeft <= soonThreshold { return .soon }
        return .normal
    }

    /// Предлагать ли записаться на сервис: с жёлтой зоны и дальше. В зелёной
    /// кнопка звала бы туда, куда ехать ещё рано.
    static func suggestsBooking(kmLeft: Int) -> Bool {
        urgency(kmLeft: kmLeft) != .normal
    }

    /// Подпись рядом с «Записаться»: почему кнопка появилась. Число — порог
    /// зоны, а не остаток: остаток крупно написан строкой выше.
    static func bookingHint(kmLeft: Int) -> String? {
        switch urgency(kmLeft: kmLeft) {
        case .normal: nil
        case .soon: "Осталось меньше \(NumberFormat.grouped(soonThreshold))\u{00A0}км"
        case .urgent where kmLeft == 0: "Самое время пройти ТО"
        case .urgent: "Осталось меньше \(NumberFormat.grouped(urgentThreshold))\u{00A0}км"
        }
    }

    /// Вторая строка карточки ТО: работы через запятую. У записи без работ —
    /// пробег: иначе карточка стояла пустой, с одним «0 ₽» (найдено
    /// 08.10.2026), а пробег — единственное, что такая запись сообщает.
    static func cardSubtitle(works: [String], mileage: Int) -> String {
        let titles = works.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return titles.isEmpty ? "На\u{00A0}\(NumberFormat.grouped(mileage))\u{00A0}км"
                              : titles.joined(separator: ", ")
    }

    /// Текст напоминания. Номер подставляется только если он есть: у машины,
    /// добавленной по названию, его нет вовсе.
    static func reminderText(name: String, plate: String, kmLeft: Int) -> String {
        let head = plate.isEmpty ? name : "\(name) \(plate)"
        // На нуле «ТО через 0 км» читается сбоем — говорим как есть.
        guard kmLeft > 0 else { return "\(head) — пробег до\u{00A0}ТО вышел" }
        return "\(head) — ТО через \(NumberFormat.grouped(kmLeft))\u{00A0}км"
    }

    /// О чём напоминание: до ТО меньше тысячи или пробег вышел совсем.
    enum ReminderStage: Int, Codable, Comparable {
        case close
        case due

        static func < (a: ReminderStage, b: ReminderStage) -> Bool { a.rawValue < b.rawValue }
    }

    /// Последнее напоминание про машину: что сказано и когда.
    struct ReminderMark: Codable, Equatable {
        var stage: ReminderStage
        var sentAt: Date
    }

    enum ReminderStep: Equatable {
        /// Зона не красная: очередь снять, отметку забыть — следующий заход
        /// в красную зону напомнит сразу.
        case clear
        /// Уже сказано, повторять рано.
        case wait
        /// Напомнить и запомнить отметку.
        case send(ReminderStage)
    }

    /// Повтор не чаще раза в неделю. Без порога напоминание уходило при
    /// каждом появлении главного экрана и каждой смене пробега, а с
    /// автопробегом пробег меняется каждую поездку (найдено 08.10.2026).
    static let reminderGap: TimeInterval = 7 * 24 * 3600

    /// Напоминать ли сейчас. Раньше недели — только если стало хуже:
    /// «меньше тысячи» сменилось на «пробег вышел».
    static func reminderStep(kmLeft: Int, mark: ReminderMark?, now: Date) -> ReminderStep {
        guard urgency(kmLeft: kmLeft) == .urgent else { return .clear }
        let stage: ReminderStage = kmLeft > 0 ? .close : .due
        guard let mark, stage <= mark.stage else { return .send(stage) }
        // Отметка из будущего — часы перевели назад; молчать из-за неё
        // до той даты нельзя.
        let since = now.timeIntervalSince(mark.sentAt)
        return since >= reminderGap || since < 0 ? .send(stage) : .wait
    }

    /// «Всего потрачено» — сумма по всем работам всех ТО.
    static func totalSpent(amounts: [Int]) -> Int {
        amounts.reduce(0, +)
    }

    /// Одометр после сохранения ТО: он не может быть меньше пробега записи.
    static func odometerAfterService(current: Int, serviceMileage: Int) -> Int {
        max(current, serviceMileage)
    }

    /// Потолок пробега при вводе. На телефоне пользователя нашлись 101 000 000
    /// и 646 464 646 км (14.10.2026) — тестовый ввод, который потом считался
    /// всерьёз. Два миллиона — с запасом даже для грузовика.
    static let maxMileage = 2_000_000

    /// Почему введённый пробег нельзя сохранить.
    enum OdometerProblem: Equatable {
        /// Меньше пробега на последнем ТО: тогда «ТО через» считалось от
        /// записи из будущего (99 799 999 км, 14.10.2026). Внутри — пробег
        /// этого ТО, его называем человеку.
        case belowService(Int)
        /// Больше `maxMileage`.
        case tooHigh

        var title: String {
            switch self {
            case .belowService: "Меньше, чем на\u{00A0}последнем ТО"
            case .tooHigh: "Слишком большой пробег"
            }
        }

        var detail: String {
            switch self {
            case .belowService(let last):
                "Последнее ТО записано на\u{00A0}\(NumberFormat.grouped(last))\u{00A0}км. "
                    + "Если там ошибка — исправьте запись в\u{00A0}истории."
            case .tooHigh:
                "Больше \(NumberFormat.grouped(maxMileage))\u{00A0}км не\u{00A0}принимаем — проверьте цифры."
            }
        }
    }

    /// Проверка ручной правки пробега. Пустое поле — это ноль: сохранение
    /// пишет в одометр ноль, и для истории ТО он такой же неверный.
    static func odometerProblem(_ value: Int?, serviceMileages: [Int]) -> OdometerProblem? {
        let value = value ?? 0
        if value > maxMileage { return .tooHigh }
        if let last = serviceMileages.max(), value < last { return .belowService(last) }
        return nil
    }
}
