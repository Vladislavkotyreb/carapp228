import Foundation

/// Подбор студийного кадра каталога по названию машины.
///
/// Каталог — 74 заранее сгенерированных кадра в `Resources/CarCatalog/`
/// (`<slug>.heic`, белая машина на чёрном, морда вправо). Слаг ищется по
/// названию машины и году поколения; не нашлось — честный `nil`, и главная
/// показывает общий ассет. Ложный матч хуже пропуска: чужая машина на
/// карточке подрывает доверие ко всему приложению, поэтому правила
/// консервативны — бренд обязан совпасть, модель обязана совпасть.
enum CarCatalog {
    /// Слаг кадра каталога или `nil`. `generation` — строка вида
    /// «X166 (2015-2026)»: первый год из неё выбирает поколение
    /// (Rio 3/4, Camry 50/70), без года берётся новейшее.
    static func slug(name: String, generation: String? = nil) -> String? {
        let tokens = normalize(name)
        guard !tokens.isEmpty else { return nil }
        let year = generation.flatMap(firstYear)

        for brand in brands where brand.aliases.contains(where: tokens.contains) {
            for rule in brand.rules {
                guard rule.groups.allSatisfy({ group in
                    tokens.contains { token in group.matches(token) }
                }) else { continue }
                if let year, let range = rule.years, !range.contains(year) { continue }
                return rule.slug
            }
            // Бренд узнали, модель — нет: правил других брендов не пробуем.
            return nil
        }
        return nil
    }

    /// Первое четырёхзначное число, похожее на год.
    static func firstYear(_ text: String) -> Int? {
        var digits = ""
        for character in text {
            if character.isNumber {
                digits.append(character)
                if digits.count == 4 {
                    if let year = Int(digits), (1950...2049).contains(year) {
                        return year
                    }
                    digits.removeFirst()
                }
            } else {
                digits = ""
            }
        }
        return nil
    }

    /// Токены названия: строчные, «ё»→«е», разделители — всё, что не буква
    /// и не цифра. «ВАЗ-21074» → ["ваз", "21074"].
    static func normalize(_ name: String) -> [String] {
        name.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    // MARK: - Таблица

    /// Группа альтернатив одного смысла: матч, если найден любой её токен.
    /// Элемент с `*` на конце сравнивается по префиксу («320d» ~ «3*»).
    struct Group {
        let tokens: [String]
        init(_ tokens: String...) { self.tokens = tokens }

        func matches(_ token: String) -> Bool {
            tokens.contains { pattern in
                pattern.hasSuffix("*")
                    ? token.hasPrefix(String(pattern.dropLast())) && token != String(pattern.dropLast())
                    : token == pattern
            }
        }
    }

    /// Правило модели: все группы должны найтись в названии. Порядок правил
    /// внутри бренда важен: специфичные («веста sw») и новейшие поколения —
    /// раньше общих.
    struct Rule {
        let slug: String
        let groups: [Group]
        var years: ClosedRange<Int>?

        init(_ slug: String, _ groups: Group..., years: ClosedRange<Int>? = nil) {
            self.slug = slug
            self.groups = groups
            self.years = years
        }
    }

    struct Brand {
        let aliases: [String]
        let rules: [Rule]

        init(_ aliases: String..., rules: [Rule]) {
            self.aliases = aliases
            self.rules = rules
        }
    }

    static let brands: [Brand] = [
        Brand("lada", "лада", "ваз", "vaz", rules: [
            Rule("lada-vesta-sw", Group("vesta", "веста"), Group("sw", "cross", "кросс")),
            Rule("lada-vesta", Group("vesta", "веста")),
            Rule("lada-granta", Group("granta", "гранта", "2190", "2191")),
            Rule("lada-priora", Group("priora", "приора", "2170", "2171", "2172")),
            Rule("lada-kalina", Group("kalina", "калина", "1118", "1119")),
            Rule("lada-largus", Group("largus", "ларгус")),
            Rule("lada-niva-travel", Group("niva", "нива"), Group("travel", "трэвел", "тревел")),
            Rule("lada-niva-legend", Group("niva", "нива", "2121", "21214", "4x4")),
            Rule("lada-xray", Group("xray", "x", "иксрей"), Group("xray", "ray", "рей", "иксрей")),
            Rule("lada-2107", Group("2107", "21074", "21072", "21070")),
            Rule("lada-2114", Group("2114", "2113", "2115", "21140")),
        ]),
        Brand("kia", "киа", rules: [
            Rule("kia-rio-4", Group("rio", "рио"), years: 2017...2049),
            Rule("kia-rio-3", Group("rio", "рио"), years: 1950...2016),
            Rule("kia-rio-4", Group("rio", "рио")),
            Rule("kia-sportage", Group("sportage", "спортейдж", "спортаж")),
            Rule("kia-cerato", Group("cerato", "церато")),
            Rule("kia-k5", Group("k5", "к5")),
            Rule("kia-ceed", Group("ceed", "сид")),
        ]),
        Brand("hyundai", "хендэ", "хенде", "хендай", "хундай", "хюндай", rules: [
            Rule("hyundai-solaris", Group("solaris", "солярис", "соларис")),
            Rule("hyundai-creta", Group("creta", "крета")),
            Rule("hyundai-tucson", Group("tucson", "туссан", "туксон")),
            Rule("hyundai-santa-fe", Group("santa", "санта"), Group("fe", "фе")),
            Rule("hyundai-elantra", Group("elantra", "элантра")),
        ]),
        Brand("toyota", "тойота", rules: [
            Rule("toyota-camry-70", Group("camry", "камри"), years: 2018...2049),
            Rule("toyota-camry-50", Group("camry", "камри"), years: 1950...2017),
            Rule("toyota-camry-70", Group("camry", "камри")),
            Rule("toyota-corolla", Group("corolla", "королла")),
            Rule("toyota-rav4", Group("rav4", "rav", "рав4", "рав")),
            Rule("toyota-lc-prado", Group("prado", "прадо")),
            Rule("toyota-lc200", Group("land", "ленд", "лэнд", "cruiser", "крузер", "lc200", "200")),
        ]),
        Brand("volkswagen", "фольксваген", "vw", rules: [
            Rule("vw-polo", Group("polo", "поло")),
            Rule("vw-tiguan", Group("tiguan", "тигуан")),
            Rule("vw-passat", Group("passat", "пассат")),
            Rule("vw-jetta", Group("jetta", "джетта")),
        ]),
        Brand("renault", "рено", rules: [
            Rule("renault-logan", Group("logan", "логан")),
            Rule("renault-sandero", Group("sandero", "сандеро")),
            Rule("renault-duster", Group("duster", "дастер")),
            Rule("renault-kaptur", Group("kaptur", "captur", "каптюр", "каптур")),
            Rule("renault-arkana", Group("arkana", "аркана")),
        ]),
        Brand("skoda", "шкода", rules: [
            Rule("skoda-octavia-a7", Group("octavia", "октавия"), years: 2013...2049),
            Rule("skoda-octavia-a5", Group("octavia", "октавия"), years: 1950...2012),
            Rule("skoda-octavia-a7", Group("octavia", "октавия")),
            Rule("skoda-rapid", Group("rapid", "рапид")),
            Rule("skoda-kodiaq", Group("kodiaq", "кодиак")),
        ]),
        Brand("nissan", "ниссан", rules: [
            Rule("nissan-almera", Group("almera", "альмера")),
            Rule("nissan-qashqai", Group("qashqai", "кашкай")),
            Rule("nissan-x-trail", Group("x", "xtrail", "икстрейл"), Group("trail", "xtrail", "трейл", "икстрейл")),
            Rule("nissan-terrano", Group("terrano", "террано")),
        ]),
        Brand("ford", "форд", rules: [
            Rule("ford-focus-3", Group("focus", "фокус"), years: 2011...2049),
            Rule("ford-focus-2", Group("focus", "фокус"), years: 1950...2010),
            Rule("ford-focus-3", Group("focus", "фокус")),
            Rule("ford-kuga", Group("kuga", "куга")),
        ]),
        Brand("chevrolet", "шевроле", rules: [
            Rule("chevrolet-niva", Group("niva", "нива")),
            Rule("chevrolet-cruze", Group("cruze", "круз")),
            Rule("chevrolet-lacetti", Group("lacetti", "лачетти")),
        ]),
        Brand("daewoo", "дэу", "деу", rules: [
            Rule("daewoo-nexia", Group("nexia", "нексия")),
            Rule("daewoo-matiz", Group("matiz", "матиз")),
        ]),
        Brand("mazda", "мазда", rules: [
            Rule("mazda-cx5", Group("cx5", "cx", "сх5", "сх")),
            Rule("mazda-3", Group("3", "три")),
            Rule("mazda-6", Group("6", "шесть")),
        ]),
        Brand("mitsubishi", "митсубиси", "мицубиси", "митсубиши", rules: [
            Rule("mitsubishi-lancer", Group("lancer", "лансер", "ланцер")),
            Rule("mitsubishi-outlander", Group("outlander", "аутлендер")),
            Rule("mitsubishi-asx", Group("asx", "асх")),
        ]),
        Brand("haval", "хавейл", "хавал", rules: [
            Rule("haval-jolion", Group("jolion", "джолион")),
        ]),
        Brand("chery", "чери", rules: [
            Rule("chery-tiggo7", Group("tiggo", "тигго"), Group("7", "7pro")),
        ]),
        Brand("geely", "джили", "джели", rules: [
            Rule("geely-coolray", Group("coolray", "кулрей")),
        ]),
        Brand("omoda", "омода", rules: [
            Rule("omoda-c5", Group("c5", "с5")),
        ]),
        Brand("bmw", "бмв", rules: [
            Rule("bmw-x5", Group("x5", "х5")),
            Rule("bmw-5-f10", Group("5", "5*", "f10")),
            Rule("bmw-3-f30", Group("3", "3*", "f30")),
        ]),
        // Без `c*`/`e*`: такой префикс ловил «class» из «GL-Class», и GL
        // получал кадр C-класса. Индексы моделей перечислены явно.
        Brand("mercedes", "мерседес", "benz", rules: [
            Rule("mercedes-gl", Group("gl", "гл", "gls", "x166")),
            Rule("mercedes-e-w212", Group("e", "е", "w212", "e200", "e220",
                                          "e250", "e300", "e350", "e400")),
            Rule("mercedes-c-w205", Group("c", "с", "w205", "c180", "c200",
                                          "c220", "c250", "c300")),
        ]),
        Brand("audi", "ауди", rules: [
            Rule("audi-a4", Group("a4", "а4")),
            Rule("audi-q5", Group("q5", "ку5")),
        ]),
        Brand("lexus", "лексус", rules: [
            Rule("lexus-rx", Group("rx", "рх")),
        ]),
        Brand("uaz", "уаз", rules: [
            Rule("uaz-patriot", Group("patriot", "патриот", "3163")),
        ]),
        Brand("opel", "опель", rules: [
            Rule("opel-astra", Group("astra", "астра")),
        ]),
        Brand("honda", "хонда", rules: [
            Rule("honda-crv", Group("crv", "cr", "срв")),
        ]),
    ]
}
