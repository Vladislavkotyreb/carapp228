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

    @Relationship(deleteRule: .cascade, inverse: \EngineFinding.check)
    var findings: [EngineFinding]

    init(date: Date = .now) {
        self.date = date
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
    var order: Int
    var check: EngineCheck?

    init(title: String, detail: String, order: Int) {
        self.title = title
        self.detail = detail
        self.order = order
    }
}
