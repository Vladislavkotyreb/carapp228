import Foundation

/// Прослушивания мотора в разговоре с сервисом: давность, подписи плашки на
/// главной и текст сводки, которую человек отправляет в сервис при записи.
///
/// Работает со значениями, а не с `EngineCheck`/`Car`: модели SwiftData сюда
/// не заходят, иначе слой перестанет собираться в `tools/run-pure-checks.sh`.
enum ListeningSummary {
    /// Через сколько дней прослушивание считаем устаревшим. Две недели — это
    /// примерно 500–1 000 км городской езды: достаточно, чтобы шум успел
    /// смениться, и мало, чтобы заставлять слушать перед каждой поездкой.
    static let staleAfterDays = 14

    /// Сколько календарных дней прошло: вчерашнее вечернее прослушивание —
    /// это «вчера», даже если прошло всего шесть часов.
    static func daysSince(_ date: Date, now: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: date)
        let to = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    static func isStale(days: Int) -> Bool {
        days > staleAfterDays
    }

    /// «сегодня», «вчера», «3 дня назад», «21 день назад».
    static func relative(days: Int) -> String {
        switch days {
        case 0: "сегодня"
        case 1: "вчера"
        default: "\(days)\u{00A0}\(plural(days, one: "день", few: "дня", many: "дней")) назад"
        }
    }

    /// Заголовок плашки на главной.
    static func title(days: Int?) -> String {
        guard let days else { return "Мотор ещё не слушали" }
        return "Слушали \(relative(days: days))"
    }

    /// Вторая строка плашки: «12 сентября · 56 400 км · Ремень привода».
    /// Пробега может не быть — у прослушиваний, сохранённых до его появления.
    static func subtitle(date: String, mileage: Int?, topFinding: String?) -> String {
        [date, mileage.map { "\(NumberFormat.grouped($0))\u{00A0}км" }, topFinding]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Подпись для машины, которую ещё не слушали: зачем это сервису.
    static let neverSubtitle = "Запишите звук мотора — сервис получит готовый диагноз"

    /// Сколько проехали от последнего ТО до прослушивания. `nil` — нечего
    /// сравнивать или данные разъехались (прослушали «раньше» ТО по пробегу).
    static func kmAfterService(checkMileage: Int?, lastServiceMileage: Int?) -> Int? {
        guard let checkMileage, let lastServiceMileage, checkMileage >= lastServiceMileage else { return nil }
        return checkMileage - lastServiceMileage
    }

    /// Дата «12 сентября» — по-русски, в родительном падеже, как в речи.
    static func dayMonth(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: date)
    }

    /// Что из прослушивания попадёт в сводку.
    struct Check: Equatable {
        let date: String
        let mileage: Int?
        let findings: [String]
    }

    /// Последнее ТО в сводке.
    struct Service: Equatable {
        let date: String
        let mileage: Int
    }

    /// Текст, который человек отправляет в сервис: в мессенджер с карточки
    /// сервиса или куда угодно через «Поделиться». Пока сервера нет, это и
    /// есть «заявка»: ровно те поля, которые потом придут в CRM.
    ///
    /// Прослушивание попадает, только если человек его приложил (`check`
    /// не `nil`): старый диагноз может увести мастера не туда.
    static func message(carName: String, plate: String, odometer: Int,
                        lastService: Service?, check: Check?) -> String {
        let head = plate.isEmpty ? carName : "\(carName), \(plate)"
        var lines = ["Здравствуйте! Хочу записаться на ТО.",
                     "\(head), пробег \(NumberFormat.grouped(odometer))\u{00A0}км."]
        if let lastService {
            lines.append("Последнее ТО — \(lastService.date), на \(NumberFormat.grouped(lastService.mileage))\u{00A0}км.")
        }
        if let check {
            let at = check.mileage.map { " на \(NumberFormat.grouped($0))\u{00A0}км" } ?? ""
            let found = check.findings.isEmpty
                ? "явных неисправностей не нашёл."
                : "похоже на: \(check.findings.map(inSentence).joined(separator: ", "))."
            lines.append("Beepy слушал мотор \(check.date)\(at) — \(found)")
        }
        return lines.joined(separator: "\n")
    }

    /// Название находки внутри фразы: «Ремень привода» → «ремень привода».
    /// Аббревиатуру в начале не трогаем: «ДВС троит» остаётся «ДВС троит».
    static func inSentence(_ title: String) -> String {
        let firstWord = title.prefix { !$0.isWhitespace }
        if firstWord.count > 1, firstWord == firstWord.uppercased() { return title }
        guard let first = title.first else { return title }
        return first.lowercased() + title.dropFirst()
    }

    /// «1 день», «2 дня», «5 дней», «11 дней», «21 день».
    static func plural(_ n: Int, one: String, few: String, many: String) -> String {
        let mod10 = n % 10
        let mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
        return many
    }
}
