import Foundation
import SwiftData

/// Одно прослушивание двигателя, подтверждённое пользователем.
///
/// Раньше история жила в `@State` внутри экрана и исчезала при перезапуске:
/// раздел, ради которого подключался разбор звука, не помнил ничего. Теперь
/// она в базе, рядом с машинами и ТО.
///
/// В базу попадает только **подтверждённое**. Находки до нажатия «Да, добавить
/// ошибки» остаются структурами `EngineIssue` в памяти экрана — иначе каждое
/// прослушивание оставляло бы за собой мусор, даже когда человек его отклонил.
@Model
final class EngineCheck {
    var date: Date

    /// Какую машину слушали. Необязательное, и не только ради миграции: у
    /// прослушиваний, сохранённых до 25.09.2026, машины нет вовсе, а выдумать
    /// её задним числом нельзя — машин могло быть две.
    var car: Car?

    /// Пробег в момент прослушивания — снимок одометра, а не ссылка на него.
    /// Сервису «на 56 400 км» говорит больше даты: по нему видно, сколько
    /// проехали после ТО и сколько — с тех пор, как мотор начал шуметь.
    var mileage: Int?

    @Relationship(deleteRule: .cascade, inverse: \EngineFinding.check)
    var findings: [EngineFinding]

    init(date: Date = .now, car: Car? = nil, mileage: Int? = nil) {
        self.date = date
        self.car = car
        self.mileage = mileage
        self.findings = []
    }
}

extension EngineCheck {
    /// Находки в том порядке, в каком их вернул разбор: он ранжированный, и
    /// перемешать его значит потерять смысл. `order` нужен именно поэтому —
    /// SwiftData порядок в связи не гарантирует.
    var orderedFindings: [EngineFinding] {
        findings.sorted { $0.order < $1.order }
    }
}

/// Одна находка внутри прослушивания: «Выпускная система — модель ставит сюда 99 %».
@Model
final class EngineFinding {
    var title: String
    var detail: String
    /// Что купить и что проверить по этой находке.
    ///
    /// Необязательное поле, и это не небрежность: у находок, сохранённых до
    /// появления советов, его в базе нет вовсе, а облегчённая миграция
    /// SwiftData добавляет молча только то, что может оставить пустым. Пусто
    /// читается как «совета нет» — именно так и было.
    var advice: String?
    var order: Int
    var check: EngineCheck?

    init(title: String, detail: String, advice: String? = nil, order: Int) {
        self.title = title
        self.detail = detail
        self.advice = advice
        self.order = order
    }
}
