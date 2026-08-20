import Foundation

/// Российский госномер формата `Б 999 ББ 999`: буква, три цифры, две буквы
/// и код региона из двух или трёх цифр.
///
/// Логика намеренно без UI и без состояния — её можно вызывать откуда угодно
/// и покрыть тестами, когда в проекте появится тестовый таргет.
enum PlateFormat {
    /// В номерах РФ используются только 12 букв, у которых есть латинские
    /// двойники. Пользователь вводит с латинской раскладки, показываем кириллицу.
    private static let latinToCyrillic: [Character: Character] = [
        "A": "А", "B": "В", "E": "Е", "K": "К", "M": "М", "H": "Н",
        "O": "О", "P": "Р", "C": "С", "T": "Т", "Y": "У", "X": "Х"
    ]

    private static let allowedLetters: Set<Character> = ["А", "В", "Е", "К", "М", "Н",
                                                         "О", "Р", "С", "Т", "У", "Х"]

    /// Максимум значимых символов: 1 буква + 3 цифры + 2 буквы + 3 цифры региона.
    private static let maxSignificant = 9
    /// После каких по счёту значимых символов ставится пробел.
    private static let spacesAfter: Set<Int> = [1, 4, 6]

    /// Приводит символ к кириллице верхнего регистра, если это возможно.
    private static func normalized(_ character: Character) -> Character {
        let upper = Character(String(character).uppercased())
        return latinToCyrillic[upper] ?? upper
    }

    /// Какой тип символа ожидается на данной позиции.
    private static func expectsDigit(at index: Int) -> Bool {
        switch index {
        case 0: return false          // буква
        case 1...3: return true       // три цифры
        case 4...5: return false      // две буквы
        default: return true          // код региона
        }
    }

    /// Оставляет только значимые символы, подходящие по позиции. Всё остальное
    /// (пробелы, дефисы, неподходящие буквы, цифра на месте буквы) отбрасывается.
    static func significant(_ raw: String) -> String {
        var result = ""
        for character in raw {
            guard result.count < maxSignificant else { break }
            let symbol = normalized(character)
            if expectsDigit(at: result.count) {
                if symbol.isNumber { result.append(symbol) }
            } else {
                if allowedLetters.contains(symbol) { result.append(symbol) }
            }
        }
        return result
    }

    /// Готовая для показа строка с автоматическими пробелами: `В 777 ОР 777`.
    static func format(_ raw: String) -> String {
        let symbols = significant(raw)
        var result = ""
        for (index, symbol) in symbols.enumerated() {
            if spacesAfter.contains(index) { result.append(" ") }
            result.append(symbol)
        }
        return result
    }

    /// Номер введён полностью. Регион допускается двух- и трёхзначный.
    static func isValid(_ raw: String) -> Bool {
        (8...9).contains(significant(raw).count)
    }

    /// Разбор на части для показа в карточке автомобиля.
    static func components(_ raw: String)
        -> (letter: String, digits: String, letters: String, region: String)? {
        let symbols = Array(significant(raw))
        guard (8...9).contains(symbols.count) else { return nil }
        return (
            letter: String(symbols[0]),
            digits: String(symbols[1...3]),
            letters: String(symbols[4...5]),
            region: String(symbols[6...])
        )
    }
}
