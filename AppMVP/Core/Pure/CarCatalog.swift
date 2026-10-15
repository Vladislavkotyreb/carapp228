import Foundation

/// Подбор студийного кадра каталога по названию машины.
///
/// Каталог — заранее сгенерированные кадры в `Resources/CarCatalog/`
/// (`<slug>.heic`, белая машина на чёрном, морда вправо). Каждому правилу
/// здесь обязан отвечать файл, и наоборот: `tools/check-catalog.py`
/// сверяет обе стороны, потому что превью на найденный слаг без файла
/// рисует пустую серую подложку. Слаг ищется по
/// названию машины и году поколения; не нашлось — честный `nil`, и главная
/// показывает общий ассет. Ложный матч хуже пропуска: чужая машина на
/// карточке подрывает доверие ко всему приложению, поэтому правила
/// консервативны — бренд обязан совпасть, модель обязана совпасть.
enum CarCatalog {
    /// Пасхалки: у конкретного госномера свой кадр, минуя подбор по модели.
    /// Ключ — номер без пробелов заглавными («Н600НА190»).
    static let plateOverrides: [String: String] = [
        "Н600НА190": "giraffe-discovery",
    ]

    /// Слаг кадра каталога или `nil`. `generation` — строка вида
    /// «X166 (2015-2026)»: первый год из неё выбирает поколение
    /// (Rio 3/4, Camry 50/70), без года берётся новейшее. `plate`
    /// проверяется первым — см. `plateOverrides`.
    static func slug(name: String, generation: String? = nil,
                     plate: String? = nil) -> String? {
        if let plate {
            let key = plate.uppercased().filter { !$0.isWhitespace }
            if let special = plateOverrides[key] { return special }
        }
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
            Rule("lada-2110", Group("2110", "2111", "2112", "21100", "21102", "21124")),
            Rule("lada-2109", Group("2109", "21099", "2108", "21093", "21083")),
            Rule("lada-2106", Group("2106", "21061", "21063", "21065")),
        ]),
        Brand("kia", "киа", rules: [
            Rule("kia-rio-4", Group("rio", "рио"), years: 2017...2049),
            Rule("kia-rio-3", Group("rio", "рио"), years: 1950...2016),
            Rule("kia-rio-4", Group("rio", "рио")),
            Rule("kia-sportage", Group("sportage", "спортейдж", "спортаж")),
            Rule("kia-cerato", Group("cerato", "церато")),
            Rule("kia-k5", Group("k5", "к5")),
            Rule("kia-ceed", Group("ceed", "сид")),
            Rule("kia-spectra", Group("spectra", "спектра")),
            Rule("kia-sorento", Group("sorento", "соренто")),
            Rule("kia-soul", Group("soul", "соул")),
            Rule("kia-seltos", Group("seltos", "селтос")),
            Rule("kia-optima", Group("optima", "оптима")),
        ]),
        Brand("hyundai", "хендэ", "хенде", "хендай", "хундай", "хюндай", rules: [
            Rule("hyundai-solaris", Group("solaris", "солярис", "соларис")),
            Rule("hyundai-creta", Group("creta", "крета")),
            Rule("hyundai-tucson", Group("tucson", "туссан", "туксон")),
            Rule("hyundai-santa-fe", Group("santa", "санта"), Group("fe", "фе")),
            Rule("hyundai-elantra", Group("elantra", "элантра")),
            Rule("hyundai-accent", Group("accent", "акцент")),
            Rule("hyundai-sonata", Group("sonata", "соната")),
            Rule("hyundai-getz", Group("getz", "гетц", "гетс")),
            Rule("hyundai-i30", Group("i30", "и30")),
        ]),
        Brand("toyota", "тойота", rules: [
            // Явный индекс кузова сильнее года: «Camry XV40» — сороковая,
            // что бы ни стояло в поколении.
            Rule("toyota-camry-40", Group("xv40", "v40", "acv40")),
            Rule("toyota-camry-70", Group("camry", "камри"), years: 2018...2049),
            Rule("toyota-camry-50", Group("camry", "камри"), years: 2011...2017),
            Rule("toyota-camry-40", Group("camry", "камри"), years: 1950...2010),
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
            Rule("vw-golf", Group("golf", "гольф")),
            Rule("vw-touareg", Group("touareg", "туарег")),
        ]),
        Brand("renault", "рено", rules: [
            Rule("renault-logan", Group("logan", "логан")),
            Rule("renault-sandero", Group("sandero", "сандеро")),
            Rule("renault-duster", Group("duster", "дастер")),
            Rule("renault-kaptur", Group("kaptur", "captur", "каптюр", "каптур")),
            Rule("renault-arkana", Group("arkana", "аркана")),
            Rule("renault-megane", Group("megane", "меган")),
            Rule("renault-fluence", Group("fluence", "флюенс")),
        ]),
        Brand("skoda", "шкода", rules: [
            Rule("skoda-octavia-a7", Group("octavia", "октавия"), years: 2013...2049),
            Rule("skoda-octavia-a5", Group("octavia", "октавия"), years: 1950...2012),
            Rule("skoda-octavia-a7", Group("octavia", "октавия")),
            Rule("skoda-rapid", Group("rapid", "рапид")),
            Rule("skoda-kodiaq", Group("kodiaq", "кодиак")),
            Rule("skoda-fabia", Group("fabia", "фабия")),
            Rule("skoda-yeti", Group("yeti", "йети", "ети")),
            Rule("skoda-superb", Group("superb", "суперб")),
            Rule("skoda-karoq", Group("karoq", "карок")),
        ]),
        Brand("nissan", "ниссан", rules: [
            Rule("nissan-almera", Group("almera", "альмера")),
            Rule("nissan-qashqai", Group("qashqai", "кашкай")),
            Rule("nissan-x-trail", Group("x", "xtrail", "икстрейл"), Group("trail", "xtrail", "трейл", "икстрейл")),
            Rule("nissan-terrano", Group("terrano", "террано")),
            Rule("nissan-juke", Group("juke", "жук", "джук")),
            Rule("nissan-note", Group("note", "ноут")),
            Rule("nissan-teana", Group("teana", "теана")),
            Rule("nissan-murano", Group("murano", "мурано")),
        ]),
        Brand("ford", "форд", rules: [
            Rule("ford-focus-3", Group("focus", "фокус"), years: 2011...2049),
            Rule("ford-focus-2", Group("focus", "фокус"), years: 1950...2010),
            Rule("ford-focus-3", Group("focus", "фокус")),
            Rule("ford-kuga", Group("kuga", "куга")),
            Rule("ford-mondeo", Group("mondeo", "мондео")),
            Rule("ford-fiesta", Group("fiesta", "фиеста")),
            Rule("ford-explorer", Group("explorer", "эксплорер")),
        ]),
        Brand("chevrolet", "шевроле", rules: [
            Rule("chevrolet-niva", Group("niva", "нива")),
            Rule("chevrolet-cruze", Group("cruze", "круз")),
            Rule("chevrolet-lacetti", Group("lacetti", "лачетти")),
            Rule("chevrolet-aveo", Group("aveo", "авео")),
            Rule("chevrolet-captiva", Group("captiva", "каптива")),
            Rule("chevrolet-cobalt", Group("cobalt", "кобальт")),
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
            Rule("mitsubishi-pajero-sport", Group("pajero", "паджеро"), Group("sport", "спорт")),
            Rule("mitsubishi-pajero-4", Group("pajero", "паджеро")),
        ]),
        Brand("haval", "хавейл", "хавал", rules: [
            Rule("haval-jolion", Group("jolion", "джолион")),
            Rule("haval-f7", Group("f7", "f7x", "ф7")),
            Rule("haval-dargo", Group("dargo", "дарго")),
        ]),
        Brand("chery", "чери", rules: [
            Rule("chery-tiggo7", Group("tiggo", "тигго"), Group("7", "7pro")),
            Rule("chery-tiggo4", Group("tiggo", "тигго"), Group("4", "4pro")),
            Rule("chery-tiggo8", Group("tiggo", "тигго"), Group("8", "8pro")),
        ]),
        Brand("geely", "джили", "джели", rules: [
            Rule("geely-coolray", Group("coolray", "кулрей")),
            Rule("geely-atlas", Group("atlas", "атлас")),
            Rule("geely-monjaro", Group("monjaro", "монджаро")),
            Rule("geely-emgrand", Group("emgrand", "эмгранд")),
        ]),
        Brand("omoda", "омода", rules: [
            Rule("omoda-c5", Group("c5", "с5")),
            Rule("omoda-s5", Group("s5")),
        ]),
        Brand("bmw", "бмв", rules: [
            // Модели с буквой — раньше серий: токен «x5» не начинается с «5».
            Rule("bmw-i4", Group("i4")),
            Rule("bmw-ix", Group("ix")),
            // Явный индекс кузова сильнее года: «BMW 525 E60», «X5 E70».
            Rule("bmw-x5-e53", Group("e53", "е53")),
            Rule("bmw-x5-e70", Group("e70", "е70")),
            Rule("bmw-x5-f15", Group("f15")),
            Rule("bmw-x5", Group("g05")),
            Rule("bmw-x6-e71", Group("e71", "е71", "e72", "е72")),
            Rule("bmw-x6-f16", Group("f16")),
            Rule("bmw-x6-g06", Group("g06")),
            Rule("bmw-x7-g07", Group("g07")),
            Rule("bmw-x3-e83", Group("e83", "е83")),
            Rule("bmw-x3", Group("f25")),
            Rule("bmw-x3-g01", Group("g01")),
            Rule("bmw-x1-e84", Group("e84", "е84")),
            Rule("bmw-x1-f48", Group("f48")),
            Rule("bmw-x1-u11", Group("u11")),
            Rule("bmw-x4-f26", Group("f26")),
            Rule("bmw-x4-g02", Group("g02")),
            Rule("bmw-x2-f39", Group("f39")),
            Rule("bmw-5-e39", Group("e39", "е39")),
            Rule("bmw-5-e60", Group("e60", "е60", "e61", "е61")),
            Rule("bmw-5-f10", Group("f10", "f11")),
            Rule("bmw-5-g30", Group("g30", "g31")),
            Rule("bmw-5-g60", Group("g60")),
            Rule("bmw-3-e46", Group("e46", "е46")),
            Rule("bmw-3-e90", Group("e90", "е90", "e91", "e92")),
            Rule("bmw-3-f30", Group("f30", "f31")),
            Rule("bmw-3-g20", Group("g20", "g21")),
            Rule("bmw-7-e65", Group("e65", "е65", "e66", "е66")),
            Rule("bmw-7-f01", Group("f01", "f02")),
            Rule("bmw-7-g11", Group("g11", "g12")),
            Rule("bmw-7-g70", Group("g70")),
            Rule("bmw-1-e87", Group("e87", "е87", "e81", "е81")),
            Rule("bmw-1-f20", Group("f20", "f21")),
            Rule("bmw-1-f40", Group("f40")),
            Rule("bmw-4-f32", Group("f32", "f33", "f36")),
            Rule("bmw-4-g26", Group("g22", "g23", "g26")),
            Rule("bmw-6-gt-g32", Group("g32")),
            Rule("bmw-8-g16", Group("g14", "g15", "g16")),
            Rule("bmw-z4-g29", Group("g29")),
            Rule("bmw-2-f44", Group("f44")),
            Rule("bmw-6-f13", Group("f12", "f13", "f06")),
            Rule("bmw-z4-e89", Group("e89", "е89")),
            Rule("bmw-2-f45", Group("f45", "f46")),
            Rule("bmw-5-gt-f07", Group("f07")),
            Rule("bmw-3-gt-f34", Group("f34")),
            // Модель и год. Порядок — от новейшего: без года берётся он.
            Rule("bmw-x5", Group("x5", "х5"), years: 2019...2049),
            Rule("bmw-x5-f15", Group("x5", "х5"), years: 2014...2018),
            Rule("bmw-x5-e70", Group("x5", "х5"), years: 2007...2013),
            Rule("bmw-x5-e53", Group("x5", "х5"), years: 1950...2006),
            Rule("bmw-x6-g06", Group("x6", "х6"), years: 2020...2049),
            Rule("bmw-x6-f16", Group("x6", "х6"), years: 2015...2019),
            Rule("bmw-x6-e71", Group("x6", "х6"), years: 1950...2014),
            Rule("bmw-x7-g07", Group("x7", "х7")),
            Rule("bmw-x3-g01", Group("x3", "х3"), years: 2018...2049),
            Rule("bmw-x3", Group("x3", "х3"), years: 2011...2017),
            Rule("bmw-x3-e83", Group("x3", "х3"), years: 1950...2010),
            Rule("bmw-x1-u11", Group("x1", "х1"), years: 2023...2049),
            Rule("bmw-x1-f48", Group("x1", "х1"), years: 2016...2022),
            Rule("bmw-x1-e84", Group("x1", "х1"), years: 1950...2015),
            Rule("bmw-x4-g02", Group("x4", "х4"), years: 2019...2049),
            Rule("bmw-x4-f26", Group("x4", "х4"), years: 1950...2018),
            Rule("bmw-x2-f39", Group("x2", "х2")),
            // Z4 и восьмёрка в каталоге только нынешние: старые кузова —
            // честный nil, а не чужой кадр.
            Rule("bmw-z4-g29", Group("z4", "з4"), years: 2019...2049),
            Rule("bmw-z4-e89", Group("z4", "з4"), years: 2009...2018),
            Rule("bmw-8-g16", Group("8", "8*"), years: 2018...2049),
            Rule("bmw-6-gt-g32", Group("6", "6*"), Group("gt", "гт"), years: 2017...2049),
            Rule("bmw-6-f13", Group("6", "6*"), years: 2011...2018),
            Rule("bmw-2-f44", Group("2", "2*"), Group("gran", "гран"), years: 2019...2049),
            Rule("bmw-2-f45", Group("2", "2*"), Group("active", "актив", "tourer", "турер")),
            // GT — раньше седанов своей серии: «530d GT» — не седан.
            Rule("bmw-5-gt-f07", Group("5", "5*"), Group("gt", "гт"), years: 1950...2016),
            Rule("bmw-3-gt-f34", Group("3", "3*"), Group("gt", "гт")),
            Rule("bmw-7-g70", Group("7", "7*"), years: 2023...2049),
            Rule("bmw-7-g11", Group("7", "7*"), years: 2016...2022),
            Rule("bmw-7-f01", Group("7", "7*"), years: 2009...2015),
            Rule("bmw-7-e65", Group("7", "7*"), years: 1950...2008),
            Rule("bmw-5-g60", Group("5", "5*"), years: 2024...2049),
            Rule("bmw-5-g30", Group("5", "5*"), years: 2017...2023),
            Rule("bmw-5-f10", Group("5", "5*"), years: 2010...2016),
            Rule("bmw-5-e60", Group("5", "5*"), years: 2003...2009),
            Rule("bmw-5-e39", Group("5", "5*"), years: 1950...2002),
            Rule("bmw-4-g26", Group("4", "4*"), years: 2021...2049),
            Rule("bmw-4-f32", Group("4", "4*"), years: 1950...2020),
            Rule("bmw-3-g20", Group("3", "3*"), years: 2019...2049),
            Rule("bmw-3-f30", Group("3", "3*"), years: 2012...2018),
            Rule("bmw-3-e90", Group("3", "3*"), years: 2005...2011),
            Rule("bmw-3-e46", Group("3", "3*"), years: 1950...2004),
            Rule("bmw-1-f40", Group("1", "1*"), years: 2020...2049),
            Rule("bmw-1-f20", Group("1", "1*"), years: 2012...2019),
            Rule("bmw-1-e87", Group("1", "1*"), years: 1950...2011),
        ]),
        // Без `c*`/`e*`: такой префикс ловил «class» из «GL-Class», и GL
        // получал кадр C-класса. Индексы моделей перечислены явно.
        Brand("mercedes", "мерседес", "benz", rules: [
            Rule("mercedes-gl", Group("gl", "гл", "gls", "x166")),
            Rule("mercedes-ml", Group("ml", "мл", "w164", "w166", "ml250",
                                      "ml280", "ml300", "ml320", "ml350")),
            // Явный индекс кузова сильнее года; дальше — по году старта
            // поколения (W212 с 2009, W205 с 2014), без года — новейшее.
            Rule("mercedes-e-w211", Group("w211")),
            Rule("mercedes-c-w204", Group("w204")),
            Rule("mercedes-e-w212", Group("e", "е", "w212", "e200", "e220",
                                          "e250", "e300", "e350", "e400"),
                 years: 2009...2049),
            Rule("mercedes-e-w211", Group("e", "е", "e200", "e220", "e240",
                                          "e280", "e320", "e350"),
                 years: 1950...2008),
            Rule("mercedes-e-w212", Group("e", "е", "w212", "e200", "e220",
                                          "e250", "e300", "e350", "e400")),
            Rule("mercedes-c-w205", Group("c", "с", "w205", "c180", "c200",
                                          "c220", "c250", "c300"),
                 years: 2014...2049),
            Rule("mercedes-c-w204", Group("c", "с", "c180", "c200", "c230",
                                          "c250", "c280", "c300"),
                 years: 1950...2013),
            Rule("mercedes-c-w205", Group("c", "с", "w205", "c180", "c200",
                                          "c220", "c250", "c300")),
        ]),
        Brand("audi", "ауди", rules: [
            Rule("audi-a4", Group("a4", "а4")),
            Rule("audi-q5", Group("q5", "ку5")),
            Rule("audi-a6-c6", Group("a6", "а6")),
            Rule("audi-q7", Group("q7", "ку7")),
        ]),
        Brand("lexus", "лексус", rules: [
            Rule("lexus-rx", Group("rx", "рх")),
        ]),
        Brand("uaz", "уаз", rules: [
            Rule("uaz-patriot", Group("patriot", "патриот", "3163")),
            Rule("uaz-hunter", Group("hunter", "хантер", "315195")),
        ]),
        Brand("opel", "опель", rules: [
            Rule("opel-astra", Group("astra", "астра")),
            Rule("opel-insignia", Group("insignia", "инсигния")),
            Rule("opel-corsa", Group("corsa", "корса")),
        ]),
        Brand("honda", "хонда", rules: [
            Rule("honda-crv", Group("crv", "cr", "срв")),
            Rule("honda-civic", Group("civic", "цивик", "сивик")),
            Rule("honda-accord", Group("accord", "аккорд")),
        ]),
        Brand("subaru", "субару", rules: [
            Rule("subaru-forester", Group("forester", "форестер")),
            Rule("subaru-outback", Group("outback", "аутбек")),
        ]),
        Brand("suzuki", "сузуки", rules: [
            Rule("suzuki-grand-vitara", Group("grand", "гранд"), Group("vitara", "витара")),
        ]),
        Brand("volvo", "вольво", rules: [
            Rule("volvo-xc60", Group("xc60", "хс60")),
        ]),
        Brand("changan", "чанган", rules: [
            Rule("changan-cs35", Group("cs35", "сs35")),
            Rule("changan-cs55", Group("cs55")),
        ]),
        Brand("exeed", "эксид", rules: [
            Rule("exeed-txl", Group("txl", "тхл")),
        ]),
        Brand("jetour", "джетур", rules: [
            Rule("jetour-x70", Group("x70", "х70")),
        ]),
        Brand("moskvich", "москвич", rules: [
            Rule("moskvich-3", Group("3", "три")),
        ]),
        Brand("jaecoo", "джейку", "джеку", rules: [
            Rule("jaecoo-j7", Group("j7")),
        ]),
        Brand("belgee", "белджи", rules: [
            Rule("belgee-x50", Group("x50", "х50")),
        ]),
    ]
}
