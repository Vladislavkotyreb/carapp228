import Foundation

/// Точка на земле в терминах чистого слоя: два числа и ничего больше.
/// `CLLocationCoordinate2D` сюда не заходит — CoreLocation остаётся снаружи,
/// как и всё, что тянет за собой систему.
struct GeoPoint: Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Расстояния на карте, подписи к ним и ответ на вопрос «это одно и то же
/// место?».
///
/// Последнее нужнее, чем кажется: добавленный в избранное бизнес приходит из
/// поиска Яндекса ещё раз, уже как найденное место, и без сверки он вставал бы
/// на карту второй точкой поверх себя же, а в списке — второй строкой.
enum MapGeo {
    /// Средний радиус Земли, метры.
    private static let earthRadius: Double = 6_371_000

    /// Расстояние по большому кругу, метры.
    ///
    /// Гаверсинус, а не `CLLocation.distance(from:)`: CoreLocation в чистый
    /// слой не заходит. На городских расстояниях расхождение со сфероидом
    /// WGS-84 — доли процента, а в подписи «1,2 км» его и не видно.
    static func meters(from origin: GeoPoint, to destination: GeoPoint) -> Double {
        let lat1 = origin.latitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let deltaLat = lat2 - lat1
        let deltaLon = (destination.longitude - origin.longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        // `min(1,…)` — от накопленной ошибки: на противоположных точках
        // подкоренное выражение вылезает за единицу, и `asin` даёт NaN.
        return 2 * earthRadius * asin(min(1, sqrt(a)))
    }

    /// Подпись расстояния в строке списка: «350 м», «1,2 км», «15 км».
    ///
    /// Точность падает с расстоянием намеренно: до соседнего дома важны
    /// десятки метров, до соседнего города — километры, и «12 480 м» никто
    /// не читает. Пробел перед единицей неразрывный: число и «км» не должны
    /// разъезжаться по строкам.
    ///
    /// Ниже десяти метров подпись не опускается: там уже врёт не округление,
    /// а сама геопозиция телефона.
    static func distanceLabel(meters: Double) -> String {
        let value = max(0, meters)
        if value < 950 {
            let tens = max(10, Int((value / 10).rounded()) * 10)
            return "\(tens)\u{00A0}м"
        }
        if value < 9_950 {
            // Десятые доли километра. Формат явно через точку и заменой на
            // запятую, а не через локаль устройства: локаль здесь выбирает
            // ещё и разделитель разрядов, и подпись разъезжалась бы с
            // остальными числами приложения.
            let km = (value / 100).rounded() / 10
            let text = String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",")
            return "\(text)\u{00A0}км"
        }
        return "\(NumberFormat.grouped(Int((value / 1000).rounded())))\u{00A0}км"
    }

    /// На сколько метров могут разойтись координаты одного и того же места.
    ///
    /// Яндекс отдаёт точку организации с разбросом от запроса к запросу, а
    /// заведения в одном доме отличаются названием — поэтому близость одна,
    /// без названия, местом не считается.
    static let sameRadius: Double = 150

    /// Одно ли это место: название совпадает по смыслу и точки стоят рядом.
    static func isSamePlace(_ one: GeoPoint, title oneTitle: String,
                            _ other: GeoPoint, title otherTitle: String) -> Bool {
        guard normalized(oneTitle) == normalized(otherTitle) else { return false }
        return meters(from: one, to: other) <= sameRadius
    }

    /// Название без того, что не меняет смысла: регистр, «ё», кавычки, знаки
    /// и лишние пробелы. «Шиномонтаж 24» и «ШИНОМОНТАЖ „24“» — одно место.
    static func normalized(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}
