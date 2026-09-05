import Foundation

/// Фрагмент распознанного текста: строка и её положение на странице в
/// нормированных координатах Vision (0…1, y растёт снизу вверх). Текстовый
/// слой PDF подаётся построчно с синтетическими координатами — алгоритму
/// всё равно, один фрагмент в ряду или несколько.
struct OCRFragment {
    let text: String
    let minX: Double
    let midY: Double

    init(_ text: String, minX: Double = 0, midY: Double = 0) {
        self.text = text
        self.minX = minX
        self.midY = midY
    }
}

/// Строка бланка: работа или запчасть с суммой.
struct ParsedWork: Equatable {
    let title: String
    let amount: Int
}

/// Что удалось вычитать из заказ-наряда.
struct ParsedServiceDoc: Equatable {
    var day: Int?
    var month: Int?
    var year: Int?
    var mileage: Int?
    var works: [ParsedWork] = []
    /// «Итого/всего к оплате» — если бланк его назвал. Для сверки, не для полей.
    var total: Int?
}

/// Разбор заказ-наряда (форма БО-14 и производные) из плоского OCR-текста.
///
/// Устройство бланка: шапка с номером и датой, данные авто с пробегом, две
/// таблицы «работы/услуги» и «запчасти/материалы» — в обеих наименование
/// слева и сумма в правой колонке, — затем итоги. Разбор построен на этом:
/// ряд с текстом слева и числом в хвосте — строка таблицы, ряды со
/// стоп-словами («итого», «НДС», «аванс»…) — служебные.
enum ServiceDocParse {
    /// Допуск группировки фрагментов в один ряд по вертикали.
    private static let rowTolerance = 0.012

    /// Служебные строки, которые нельзя записывать работами.
    private static let stopWords = [
        "итого", "всего", "ндс", "скидк", "аванс", "оплат", "наличн",
        "безнал", "сдача", "задолж", "предоплат", "прописью", "подпись",
        "заказчик", "исполнитель", "мастер", "приемщик", "гаранти",
        "телефон", "адрес", "инн", "огрн", "квитанц", "наименование",
        "кол-во", "цена", "сумма", "стоимост",
        // строки про сам автомобиль: хвост госномера или года выпуска
        // иначе принимается за сумму
        "автомобил", "гос. номер", "госномер", "vin", "марка", "модель",
        "владел", "клиент", "пробег"
    ]

    /// Итоговые строки — из них берётся `total`.
    private static let totalWords = ["итого", "всего к оплате", "к оплате"]

    static func parse(_ fragments: [OCRFragment]) -> ParsedServiceDoc {
        var doc = ParsedServiceDoc()

        for row in rows(from: fragments) {
            let lowered = row.lowercased()

            if doc.day == nil, let (d, m, y) = date(in: row) {
                doc.day = d; doc.month = m; doc.year = y
            }
            if doc.mileage == nil, let km = mileage(in: lowered) {
                doc.mileage = km
            }

            guard let amount = trailingAmount(of: row) else { continue }

            if totalWords.contains(where: lowered.contains) {
                // Итогов в бланке несколько (работы, запчасти, всего) —
                // финальный обычно наибольший.
                doc.total = max(doc.total ?? 0, amount)
                continue
            }
            guard !stopWords.contains(where: lowered.contains) else { continue }

            let title = self.title(of: row)
            guard title.count >= 3, doc.works.count < 30 else { continue }
            doc.works.append(ParsedWork(title: title, amount: amount))
        }
        return doc
    }

    // MARK: - Ряды

    /// Склеивает фрагменты в ряды по вертикали: верхние сначала, в ряду —
    /// слева направо.
    static func rows(from fragments: [OCRFragment]) -> [String] {
        var groups: [(y: Double, items: [OCRFragment])] = []
        for fragment in fragments {
            if let index = groups.firstIndex(where: { abs($0.y - fragment.midY) < rowTolerance }) {
                groups[index].items.append(fragment)
            } else {
                groups.append((fragment.midY, [fragment]))
            }
        }
        return groups
            .sorted { $0.y > $1.y }
            .map { group in
                group.items.sorted { $0.minX < $1.minX }
                    .map(\.text).joined(separator: " ")
            }
    }

    // MARK: - Сумма в хвосте ряда

    /// Последняя числовая последовательность ряда: «Замена масла 2 500,00» →
    /// 2500. Разряды в бланках разделяют пробелами, поэтому числовые токены
    /// подряд склеиваются; копейки отбрасываются округлением.
    static func trailingAmount(of row: String) -> Int? {
        var tokens = row.split(whereSeparator: { $0 == " " || $0 == "\u{00A0}" }).map(String.init)
        // «₽» и «руб.» в хвосте — не часть числа
        while let last = tokens.last?.lowercased(),
              last == "₽" || last.hasPrefix("руб") || last == "р." {
            tokens.removeLast()
        }

        var numeric: [String] = []
        for token in tokens.reversed() {
            guard isNumericToken(token) else { break }
            numeric.insert(token, at: 0)
        }
        guard !numeric.isEmpty else { return nil }

        let joined = numeric.joined().replacingOccurrences(of: ",", with: ".")
        guard let value = Double(joined), value >= 1, value < 10_000_000 else { return nil }
        // Копейки отбрасываются: поля формы — целые рубли.
        return Int(value)
    }

    private static func isNumericToken(_ token: String) -> Bool {
        !token.isEmpty && token.allSatisfy { $0.isNumber || $0 == "," || $0 == "." }
            && token.contains(where: \.isNumber)
    }

    /// Название — фрагмент ряда до начала числовых колонок. Ведущий номер
    /// строки таблицы («1», «2.») отбрасывается.
    static func title(of row: String) -> String {
        var tokens = Array(row.split(separator: " "))
        while let first = tokens.first, isNumericToken(String(first)) {
            tokens.removeFirst()
        }
        var titleTokens: [Substring] = []
        for token in tokens {
            if isNumericToken(String(token)), !titleTokens.isEmpty { break }
            titleTokens.append(token)
        }
        let raw = titleTokens.joined(separator: " ")
        let letters = raw.filter(\.isLetter)
        guard letters.count >= 3 else { return "" }
        return raw.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Дата и пробег

    /// «14.08.2026», «14/08/26» — первая правдоподобная дата в документе.
    /// `NSRegularExpression`, а не regex-литерал: прогон pure-checks собирает
    /// файл голым `swiftc`, где bare-slash может быть выключен.
    private static let dateRegex = try! NSRegularExpression(
        pattern: #"(\d{1,2})[./](\d{1,2})[./](\d{2,4})"#)

    static func date(in row: String) -> (Int, Int, Int)? {
        let all = NSRange(row.startIndex..., in: row)
        guard let match = dateRegex.firstMatch(in: row, options: [], range: all),
              let dayRange = Range(match.range(at: 1), in: row),
              let monthRange = Range(match.range(at: 2), in: row),
              let yearRange = Range(match.range(at: 3), in: row),
              let d = Int(row[dayRange]), let m = Int(row[monthRange]),
              var y = Int(row[yearRange]),
              (1...31).contains(d), (1...12).contains(m) else { return nil }
        if y < 100 { y += 2000 }
        guard (2000...2100).contains(y) else { return nil }
        return (d, m, y)
    }

    /// Пробег: число в ряду со словом «пробег» или перед «км». Разряды в
    /// бланках разделяют пробелами («92 450 км») — числовые токены подряд
    /// склеиваются, как и в суммах.
    static func mileage(in lowered: String) -> Int? {
        guard lowered.contains("пробег") || lowered.contains(" км") else { return nil }
        let tokens = lowered.split(whereSeparator: { $0 == " " || $0 == "\u{00A0}" || $0 == ":" })
        var candidates: [Int] = []
        var run = ""
        for token in tokens {
            if token.allSatisfy(\.isNumber) {
                run += token
            } else {
                if let value = Int(run) { candidates.append(value) }
                run = ""
            }
        }
        if let value = Int(run) { candidates.append(value) }
        return candidates.filter { $0 >= 100 && $0 < 3_000_000 }.max()
    }
}
