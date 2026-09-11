import Foundation

/// Разбор звука двигателя через `cardiag` — открытый проект adam-s/car-diagnosis
/// (MIT). Пайплайн там на Python: запись чистится каскадом, кодируется моделью
/// CLAP и разбирается линейными головами. На устройстве это не поднять, поэтому
/// приложение отдаёт запись его же веб-серверу (`cardiag serve`).
///
/// Проект честно называет себя triage aid, а не диагностом: fault/normal он
/// угадывает с AUROC 0.79, зону из шести — в топ-3 примерно в 75 % случаев,
/// конкретную деталь — в 45–65 %. Поэтому в интерфейсе результат подаётся как
/// «на что посмотреть», и уверенность указывается рядом.
enum DiagnosisEndpoint {
    /// Адрес сервера. Сейчас это Mac разработчика в домашней сети — на другой
    /// сети адрес сменится, и его надо поправить здесь. Если сервер не
    /// отвечает, экран честно скажет об этом, а не подсунет выдуманные находки.
    ///
    /// Поднимается так:
    /// ```
    /// cd car-diagnosis && source .venv/bin/activate
    /// cardiag serve --model models --host 0.0.0.0 --port 8077
    /// ```
    /// Именно `--host 0.0.0.0`: по умолчанию сервер слушает 127.0.0.1 и с
    /// телефона недоступен. Пустая строка здесь возвращает работу на заглушку.
    static let baseURL = "http://192.168.1.141:8077"

    static var isConfigured: Bool { !baseURL.isEmpty }
}

/// Ответ `POST /diagnose`. Поля повторяют `Diagnosis.to_dict` из репозитория.
struct Diagnosis: Decodable {
    /// `fault` | `normal` | `uncertain`
    let verdict: String
    let faultProbability: Double
    let engineKnockProbability: Double
    let regions: [Region]
    let causes: [Cause]
    /// Оговорка самого пайплайна про то, что это триаж, а не приговор.
    let note: String
    /// Сколько чистых механических кусков каскад выделил из записи.
    ///
    /// Ноль — важный сигнал, а не мелочь: значит звука двигателя в записи не
    /// нашлось и разбирали её целиком. Голова причин при этом всё равно
    /// раскладывает свои 100 % по деталям — на пятисекундной тишине она даёт
    /// «выхлоп 100 %». Без этой проверки экран уверенно показывал бы выдумку.
    let segmentCount: Int
    /// В ответе без модели приходит `false` и одна только чистка звука.
    let modelLoaded: Bool

    /// Прошла ли запись привратника «это вообще звук мотора».
    ///
    /// Считает его наш сервер (`tools/diagnosis_server.py`) через CLAP, потому
    /// что сам cardiag такого вопроса не задаёт: его головы обучены отличать
    /// неисправный мотор от исправного и варианта «это не машина» не знают.
    /// Без привратника тихая комната уверенно превращалась в «дифференциал».
    let isEngine: Bool
    /// Насколько запись похожа на мотор, 0…1. Порог на сервере 0.5.
    let engineProbability: Double
    /// Что в записи прозвучало громче всего, если это не мотор.
    ///
    /// Код приходит с сервера готовым, а не собирается здесь из долей по
    /// промптам: формулировки промптов живут на сервере, и держать их копию
    /// в приложении значит однажды разойтись и начать врать с экрана.
    let heard: HeardKind

    enum HeardKind: String, Decodable {
        case engine, speech, music, silence, unknown

        /// Чем объяснить человеку отказ. Формулировки — про то, что делать,
        /// а не про то, что случилось: «слышно речь» без продолжения ничего
        /// не подсказывает.
        var explanation: String {
            switch self {
            case .speech:
                "Слышны в основном голоса. Запишите ещё раз, не разговаривая."
            case .music:
                "Мешает посторонний шум. Запишите ближе к мотору, где потише."
            case .silence:
                "В записи почти тишина. Заведите двигатель и поднесите телефон ближе."
            case .engine:
                // Сюда попадаем, только когда «мотор» победил остальные, но
                // не дотянул до порога: звук похож на двигатель и всё же
                // слишком слабый. Говорить «мотора не слышно» здесь неправда.
                "Мотор слышно слабо. Поднесите телефон ближе к работающему двигателю."
            case .unknown:
                "В записи не слышно работающего мотора. Заведите двигатель и поднесите телефон ближе."
            }
        }
    }

    struct Region: Decodable {
        /// Одна из шести зон: engine, accessory, exhaust, drivetrain,
        /// suspension/steering, brakes/wheels
        let zone: String
        let p: Double
    }

    struct Cause: Decodable {
        /// Семейство неисправности, например `wheel_bearing`
        let part: String
        let p: Double
        let note: String
    }

    enum CodingKeys: String, CodingKey {
        case verdict
        case faultProbability = "fault_probability"
        case engineKnockProbability = "engine_knock_probability"
        case regions, causes, note, segments
        case modelLoaded = "model_loaded"
        case isEngine = "is_engine"
        case engineProbability = "engine_probability"
        case heard
    }

    /// Куски нужны только числом, поэтому декодируем их как непрозрачный
    /// список: полей у сегмента шесть, и ни одно на экран не идёт.
    private struct AnySegment: Decodable {}

    /// Локальный разбор (`LocalDiagnosis`) собирает тот же ответ без JSON.
    /// Сегментов у него нет по построению — каскад изоляции не портирован,
    /// значение всегда ноль, как фактически было у телефонных записей
    /// и на сервере.
    init(verdict: String, faultProbability: Double, engineKnockProbability: Double,
         regions: [Region], causes: [Cause], note: String,
         isEngine: Bool, engineProbability: Double, heard: HeardKind) {
        self.verdict = verdict
        self.faultProbability = faultProbability
        self.engineKnockProbability = engineKnockProbability
        self.regions = regions
        self.causes = causes
        self.note = note
        self.segmentCount = 0
        self.modelLoaded = true
        self.isEngine = isEngine
        self.engineProbability = engineProbability
        self.heard = heard
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        verdict = try box.decodeIfPresent(String.self, forKey: .verdict) ?? "uncertain"
        faultProbability = try box.decodeIfPresent(Double.self, forKey: .faultProbability) ?? 0
        engineKnockProbability = try box.decodeIfPresent(Double.self,
                                                         forKey: .engineKnockProbability) ?? 0
        regions = try box.decodeIfPresent([Region].self, forKey: .regions) ?? []
        causes = try box.decodeIfPresent([Cause].self, forKey: .causes) ?? []
        note = try box.decodeIfPresent(String.self, forKey: .note) ?? ""
        modelLoaded = try box.decodeIfPresent(Bool.self, forKey: .modelLoaded) ?? false
        segmentCount = (try box.decodeIfPresent([AnySegment].self, forKey: .segments) ?? []).count
        // Старый `cardiag serve` полей привратника не присылает вовсе. Тогда
        // считаем запись мотором: иначе прежний сервер молча перестал бы
        // работать, а это хуже, чем отсутствие проверки.
        isEngine = try box.decodeIfPresent(Bool.self, forKey: .isEngine) ?? true
        engineProbability = try box.decodeIfPresent(Double.self, forKey: .engineProbability) ?? 1
        heard = (try? box.decodeIfPresent(HeardKind.self, forKey: .heard)) ?? .unknown
    }
}

enum DiagnosisError: LocalizedError {
    case notConfigured
    case badAddress
    case server(String)
    case transport

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Сервер диагностики не настроен"
        case .badAddress: "Неверный адрес сервера"
        case .server(let text): text
        case .transport: "Сервер диагностики недоступен"
        }
    }
}

/// Клиент `cardiag`. Отдельным типом, а не методом вью: разбор звука ещё
/// поменяется (сервер может уехать в облако), а интерфейс от этого зависеть
/// не должен.
enum CarDiagnosisClient {
    /// Загружает запись и отдаёт разбор. Форма запроса — обычная
    /// `multipart/form-data` с полем `file`, ровно как ждёт `web/app.py`.
    ///
    /// Заголовок `Origin` намеренно не ставится: сервер отбивает межсайтовые
    /// запросы по нему, а у родного клиента его и не должно быть.
    static func diagnose(fileURL: URL) async throws -> Diagnosis {
        guard DiagnosisEndpoint.isConfigured else { throw DiagnosisError.notConfigured }
        guard let url = URL(string: DiagnosisEndpoint.baseURL + "/diagnose") else {
            throw DiagnosisError.badAddress
        }

        let boundary = "cardiag.\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        // Разбор идёт через CLAP и занимает секунды, а на холодном старте —
        // и полминуты: модель поднимается лениво, первым запросом.
        request.timeoutInterval = 120

        let audio: Data
        do { audio = try Data(contentsOf: fileURL) } catch { throw DiagnosisError.transport }

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; "
                    + "filename=\"\(fileURL.lastPathComponent)\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.upload(for: request, from: body)
        } catch {
            throw DiagnosisError.transport
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            // Сервер отвечает 400/413 с полем `error` и никогда не 500 —
            // текст оттуда понятнее любого нашего.
            let text = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw DiagnosisError.server(text ?? "Сервер вернул ошибку \(http.statusCode)")
        }

        do {
            return try JSONDecoder().decode(Diagnosis.self, from: data)
        } catch {
            throw DiagnosisError.server("Непонятный ответ сервера")
        }
    }
}

private extension Data {
    mutating func append(_ text: String) {
        if let chunk = text.data(using: .utf8) { append(chunk) }
    }
}

/// Русские названия для словаря `cardiag`. Списки взяты из
/// `pipeline/build.py`: шесть зон и семейства неисправностей, разложенные по
/// ним. Держим полностью, а не «что попалось»: незнакомое семейство иначе
/// доедет до экрана английским идентификатором вроде `wheel_bearing`.
enum DiagnosisVocabulary {
    static func zone(_ key: String) -> String {
        switch key {
        case "engine": "Двигатель"
        case "accessory": "Навесное оборудование"
        case "exhaust": "Выпускная система"
        case "drivetrain": "Трансмиссия"
        case "suspension/steering": "Подвеска и рулевое"
        case "brakes/wheels": "Тормоза и колёса"
        default: key
        }
    }

    /// Зона, к которой пайплайн относит семейство. Раскладка та же, что в
    /// `_REGION` из `pipeline/build.py`, — сервер присылает зоны отдельным
    /// списком, но там они общие для всей записи, а на карточке нужна своя.
    static func zone(forPart key: String) -> String {
        switch key {
        case "engine_internal", "rod_knock", "valvetrain", "low_oil",
             "fuel_ignition", "fuel_pump":
            "Двигатель"
        case "belt", "alternator", "water_pump", "ac_compressor", "accessories":
            "Навесное оборудование"
        case "exhaust", "turbo":
            "Выпускная система"
        case "cv_axle", "cv_joint", "differential":
            "Трансмиссия"
        case "suspension", "power_steering":
            "Подвеска и рулевое"
        case "brakes", "wheel_bearing", "bad_wheal_bearing", "wheel_tire", "tires":
            "Тормоза и колёса"
        case "transmission":
            "Трансмиссия"
        case "cooling_other":
            "Система охлаждения"
        case "mounts":
            "Опоры двигателя"
        default:
            "Не определено"
        }
    }

    static func part(_ key: String) -> String {
        switch key {
        case "engine_internal": "Внутри двигателя"
        case "rod_knock": "Стук шатунных вкладышей"
        case "valvetrain": "Газораспределительный механизм"
        case "low_oil": "Низкий уровень масла"
        case "fuel_ignition": "Топливо и зажигание"
        case "fuel_pump": "Топливный насос"
        case "belt": "Ремень привода"
        case "alternator": "Генератор"
        case "water_pump": "Помпа"
        case "ac_compressor": "Компрессор кондиционера"
        case "accessories": "Навесное оборудование"
        case "exhaust": "Выпускная система"
        case "turbo": "Турбина"
        case "cv_joint": "ШРУС"
        case "cv_axle": "Приводной вал"
        case "differential": "Дифференциал"
        case "suspension": "Подвеска"
        case "power_steering": "Усилитель руля"
        case "brakes": "Тормоза"
        // Два класса ступичного подшипника — не опечатка здесь, а опечатка в
        // разметке самой модели: в ней рядом живут `wheel_bearing` и
        // `bad_wheal_bearing`. Оба ведём в одно название.
        case "wheel_bearing", "bad_wheal_bearing": "Ступичный подшипник"
        case "wheel_tire", "tires": "Колёса и шины"
        case "transmission": "Коробка передач"
        case "cooling_other": "Система охлаждения"
        case "mounts": "Опоры двигателя"
        case "other": "Что-то другое"
        case "none": "Ничего определённого"
        default: key
        }
    }

    /// Что купить и что посмотреть, если модель поставила сюда.
    ///
    /// Ключи те же, что у `part(_:)`, и список держится рядом с ним намеренно:
    /// разойдись они — деталь получила бы чужой совет, причём молча. Незнакомое
    /// семейство остаётся без строки: пустая строка честнее выдуманной.
    ///
    /// Формулировки — про расходники и про одну проверку, которую можно сделать
    /// до покупки. Разбор звука угадывает деталь в половине случаев, поэтому
    /// «купить» здесь никогда не значит «уже неисправно»: сначала проверка.
    static func advice(forPart key: String) -> String? {
        guard let hint = consumables(key) else { return nil }
        return "Купить: \(hint.buy). Проверить: \(hint.check)."
    }

    /// Расходники и проверка по семейству неисправности.
    private static func consumables(_ key: String) -> (buy: String, check: String)? {
        switch key {
        case "engine_internal":
            return ("моторное масло и\u{00A0}фильтр — пригодятся после ремонта",
                    "компрессию и\u{00A0}давление масла на\u{00A0}сервисе")
        case "rod_knock":
            return ("моторное масло и\u{00A0}маслофильтр",
                    "уровень масла; до\u{00A0}осмотра не\u{00A0}крутить высокие обороты")
        case "valvetrain":
            return ("масло, маслофильтр, прокладку клапанной крышки",
                    "зазоры клапанов и\u{00A0}натяжение цепи или ремня ГРМ")
        case "low_oil":
            return ("моторное масло вашего допуска и\u{00A0}маслофильтр",
                    "уровень по\u{00A0}щупу и\u{00A0}поддон на\u{00A0}потёки")
        case "fuel_ignition":
            return ("свечи зажигания, топливный фильтр",
                    "ошибки сканером и\u{00A0}состояние катушек")
        case "fuel_pump":
            return ("топливный фильтр и\u{00A0}сетку насоса",
                    "давление в\u{00A0}топливной рампе")
        case "belt", "accessories":
            return ("ремень навесного оборудования, натяжной и\u{00A0}обводной ролики",
                    "ремень на\u{00A0}трещины, ролики — рукой на\u{00A0}люфт и\u{00A0}гул")
        case "alternator":
            return ("ремень генератора, щётки",
                    "напряжение на\u{00A0}клеммах при работающем моторе")
        case "water_pump":
            return ("помпу, антифриз, прокладку",
                    "люфт шкива и\u{00A0}потёки из\u{00A0}дренажного отверстия")
        case "ac_compressor":
            return ("ремень компрессора",
                    "звук с\u{00A0}включённым и\u{00A0}выключенным кондиционером")
        case "exhaust":
            return ("прокладки, хомуты, подвесные резинки глушителя",
                    "трубу и\u{00A0}банки на\u{00A0}прогар, крепления — на\u{00A0}обрыв")
        case "turbo":
            return ("масло, маслофильтр, патрубки интеркулера",
                    "патрубки на\u{00A0}подсос и\u{00A0}люфт вала турбины")
        case "cv_joint", "cv_axle":
            return ("ШРУС в\u{00A0}сборе или ремкомплект с\u{00A0}пыльником и\u{00A0}смазкой",
                    "пыльники на\u{00A0}разрывы, хруст — в\u{00A0}повороте до\u{00A0}упора")
        case "differential":
            return ("трансмиссионное масло, при течи — сальники",
                    "уровень масла и\u{00A0}сальники на\u{00A0}потёки")
        case "suspension":
            return ("амортизаторы или стойки, опоры, отбойники",
                    "стойки на\u{00A0}потёки, сайлентблоки — на\u{00A0}разрывы")
        case "power_steering":
            return ("жидкость ГУР, при течи — шланги",
                    "уровень жидкости и\u{00A0}рейку на\u{00A0}потёки")
        case "brakes":
            return ("тормозные колодки, при износе — диски",
                    "толщину колодок и\u{00A0}бортик на\u{00A0}дисках")
        case "wheel_bearing", "bad_wheal_bearing":
            return ("ступичный подшипник, ступичную гайку",
                    "люфт колеса на\u{00A0}подъёмнике; гул меняется в\u{00A0}повороте")
        case "wheel_tire", "tires":
            return ("шины по\u{00A0}сезону, грузики для балансировки",
                    "давление, износ протектора и\u{00A0}биение на\u{00A0}балансировке")
        case "transmission":
            return ("масло в\u{00A0}коробку и\u{00A0}фильтр",
                    "уровень масла; рывки и\u{00A0}гул — показать мастеру")
        case "cooling_other":
            return ("антифриз, патрубки, термостат",
                    "уровень антифриза и\u{00A0}радиатор на\u{00A0}потёки")
        case "mounts":
            return ("опоры двигателя",
                    "подушки на\u{00A0}трещины, качание мотора на\u{00A0}оборотах")
        default:
            // «other», «none» и всё, чего мы не знаем: совет без деталей —
            // это выдумка, а выдумке на экране не место.
            return nil
        }
    }
}
