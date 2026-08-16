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
    static let baseURL = "http://192.168.1.108:8077"

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
    }

    /// Куски нужны только числом, поэтому декодируем их как непрозрачный
    /// список: полей у сегмента шесть, и ни одно на экран не идёт.
    private struct AnySegment: Decodable {}

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
}
