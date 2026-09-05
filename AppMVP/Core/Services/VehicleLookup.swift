import Foundation

/// Данные машины, полученные по госномеру.
/// VIN и поколение опциональны: не каждый поставщик их отдаёт, а некоторые
/// присылают VIN замаскированным звёздочками — такое значение бесполезно.
struct FoundVehicle: Equatable {
    let name: String
    var vin: String?
    var generation: String?
    var odometer: Int?
    /// Год выпуска. Отдаёт только AvtoVinCod; в модель `Car` пока не
    /// сохраняется — показывается в шторке подтверждения.
    var year: Int?

    /// Замаскированный VIN считаем отсутствующим.
    var displayVIN: String? {
        guard let vin, !vin.isEmpty, !vin.contains("*") else { return nil }
        return vin
    }
}

enum VehicleLookupError: Error {
    /// Номера нет в базе — состояние из макета «Мы не нашли такого номера».
    case notFound
    /// Сеть или поставщик недоступны.
    case unavailable
}

/// Поиск машины по госномеру.
protocol VehicleLookup: Sendable {
    func lookup(plate: String) async throws -> FoundVehicle
}

/// Сессия обоих поставщиков: эфемерная, без дискового кэша и кук.
/// Ответы поиска — госномер и VIN, то есть персональные данные; общий
/// `URLSession.shared` мог бы отложить их в нешифрованный кэш на диске.
private let lookupSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.urlCache = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: config)
}()

/// Поставщик для экранов: настоящий, когда токен на месте, и заглушка из
/// макета, пока его нет, — тот же приём, что у раздела «Карта» без ключа.
/// AvtoVinCod предпочтительнее: он отдаёт год выпуска и доступен физлицу
/// без месячных платежей.
enum VehicleLookupProvider {
    static func make() -> any VehicleLookup {
        if VehicleLookupKey.hasAvtoVinCod { return AvtoVinCodLookup() }
        if VehicleLookupKey.hasAPICloud { return RSAVehicleLookup() }
        return StubVehicleLookup()
    }
}

/// Поиск через avtovincod.ru, метод `gos2vin`: VIN, марка, модель, год
/// выпуска. Доступен физлицам и самозанятым, ненайденный номер бесплатный.
struct AvtoVinCodLookup: VehicleLookup {
    func lookup(plate: String) async throws -> FoundVehicle {
        // API ждёт номер слитно кириллицей: «В777ОР777».
        let compact = PlateFormat.significant(plate)
        guard !compact.isEmpty else { throw VehicleLookupError.notFound }

        var components = URLComponents(string: "https://api.avtovincod.ru/gos2vin")!
        components.queryItems = [URLQueryItem(name: "plate", value: compact)]
        guard let url = components.url else { throw VehicleLookupError.unavailable }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(VehicleLookupKey.avtoVinCodToken)",
                         forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await lookupSession.data(for: request)
        } catch {
            throw VehicleLookupError.unavailable
        }

        // 404 задокументирован как «номер не найден» — это состояние макета.
        // Остальные не-200 (401 токен, 402 баланс, 429 частота) — недоступность.
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            throw VehicleLookupError.notFound
        }

        guard let reply = try? JSONDecoder().decode(Gos2VinResponse.self, from: data),
              reply.success == 1 else {
            throw VehicleLookupError.unavailable
        }

        let name = Self.prettyName([reply.brand, reply.model].compactMap { $0 }
            .joined(separator: " "))
        guard !name.isEmpty else { throw VehicleLookupError.notFound }
        return FoundVehicle(name: name, vin: reply.vin, year: reply.year)
    }

    /// Сервис отдаёт марку и модель в нижнем регистре («volkswagen multivan»
    /// — снято живым запросом). `capitalized` поднимает первые буквы слов и
    /// частей через дефис; короткие латинские слова — аббревиатуры: gl → GL,
    /// bmw → BMW. Кириллицу («Лада») правило не трогает.
    private static func prettyName(_ raw: String) -> String {
        raw.capitalized.split(separator: " ").map { word in
            word.count <= 3 && word.allSatisfy { $0.isLetter && $0.isASCII }
                ? word.uppercased() : String(word)
        }.joined(separator: " ")
    }
}

/// Ответ `gos2vin`. Поля, которых здесь нет, приходят, но не используются.
private struct Gos2VinResponse: Decodable {
    let success: Int?
    let vin: String?
    let brand: String?
    let model: String?
    let year: Int?
}

/// Поиск по базе полисов ОСАГО (НСИС/РСА) через api-cloud.ru — открытый
/// источник, где по одному госномеру отдают марку с моделью и VIN.
/// Года выпуска, поколения и пробега там нет; VIN бывает замаскирован
/// звёздочками — такой отсеивает `FoundVehicle.displayVIN`.
struct RSAVehicleLookup: VehicleLookup {
    func lookup(plate: String) async throws -> FoundVehicle {
        // API ждёт номер слитно кириллицей: «В777ОР777».
        let compact = PlateFormat.significant(plate)
        guard !compact.isEmpty else { throw VehicleLookupError.notFound }

        var components = URLComponents(string: "https://api-cloud.ru/api/rsa.php")!
        components.queryItems = [
            URLQueryItem(name: "type", value: "osago"),
            URLQueryItem(name: "regNumber", value: compact)
        ]
        guard let url = components.url else { throw VehicleLookupError.unavailable }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // Токен — заголовком, а не в query: URL с токеном оседает в кэшах и
        // логах промежуточных узлов. Документация допускает оба способа.
        request.setValue(VehicleLookupKey.apiCloudToken, forHTTPHeaderField: "Token")

        let data: Data
        do {
            (data, _) = try await lookupSession.data(for: request)
        } catch {
            throw VehicleLookupError.unavailable
        }

        guard let response = try? JSONDecoder().decode(RSAResponse.self, from: data) else {
            throw VehicleLookupError.unavailable
        }
        // 200 с пустым rez — «сведения не найдены», это notFound из макета.
        // Остальные статусы (неверный токен 499, пустой баланс 498, таймаут
        // источника 404) — недоступность, номер тут ни при чём.
        guard response.status == 200 else { throw VehicleLookupError.unavailable }

        // Полисов на номер может быть несколько (страховка перезаключалась);
        // действующий говорит о машине надёжнее прекращённого.
        let entries = response.rez ?? []
        let entry = entries.first { $0.status == "Действует" } ?? entries.first
        guard let entry, let name = entry.brandmodel, !name.isEmpty else {
            throw VehicleLookupError.notFound
        }
        return FoundVehicle(name: name, vin: entry.vin)
    }
}

/// Ответ `rsa.php`. Поля, которых здесь нет, приходят, но не используются.
/// `status` необязательный: ошибки сервис отдаёт в другой форме —
/// `{"error":"503","message":…}` без него вовсе (снято curl-ом).
private struct RSAResponse: Decodable {
    let status: Int?
    let rez: [Entry]?

    struct Entry: Decodable {
        let brandmodel: String?
        let vin: String?
        /// Статус полиса: «Действует» или «Прекращён». Не путать с `status`
        /// верхнего уровня — тот числовой код ответа.
        let status: String?
    }
}

/// Заглушка до подключения токена: любой корректный номер находит машину
/// с данными из макета (node 45854:2936).
struct StubVehicleLookup: VehicleLookup {
    func lookup(plate: String) async throws -> FoundVehicle {
        guard PlateFormat.isValid(plate) else { throw VehicleLookupError.notFound }
        return FoundVehicle(
            name: "Mercedes-Benz GL-класс",
            vin: "423423432FRFRIFR",
            generation: "X166 (2015-2026)",
            odometer: 9_000_000
        )
    }
}
