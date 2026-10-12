import Foundation

/// Автопробег: подсчёт пути поездки по отсчётам геопозиции.
///
/// Поездку начинает и заканчивает команда («Быстрые команды», автоматизация
/// по Bluetooth машины), между ними `TripTracker` кормит сюда отсчёты. Здесь
/// решается, какой отсчёт годен, сколько метров он добавил и сколько целых
/// километров уходит в пробег. Линию маршрута для экрана поездки собирает
/// `TripTrack` ниже.
enum TripMath {
    /// Отсчёт геопозиции — то, что нужно от `CLLocation`, без CoreLocation.
    struct Sample: Equatable, Codable {
        var latitude: Double
        var longitude: Double
        /// Горизонтальная точность, м. Отрицательная — отсчёт негодный.
        var accuracy: Double
        /// Секунды от любого общего начала.
        var time: Double
    }

    /// Что отсчёт значит для поездки.
    enum Step: Equatable {
        /// Не годится или не сдвинулись: опора остаётся прежней.
        case skip
        /// Первый годный отсчёт: становится опорой, пути не добавляет.
        case anchor
        /// Сдвинулись на столько метров; отсчёт — новая опора.
        case move(Double)
    }

    /// Хуже 50 м отсчёт не берём: это вышки и Wi-Fi, а не спутники.
    static let maxAccuracy: Double = 50
    /// Меньше 8 м — дрожь стоящего телефона, а не движение: без порога она
    /// за час стоянки с заведённым мотором набегала бы сотнями метров.
    static let minStep: Double = 8
    /// 70 м/с — 252 км/ч. Быстрее — скачок геопозиции, а не машина.
    static let maxSpeed: Double = 70
    /// Короче 100 м поездку не записываем: телефон подключился к машине на
    /// парковке, и никто никуда не поехал.
    static let minTrip: Double = 100
    /// Поездка длиннее 12 часов считается забытой: команда «Закончить» не
    /// пришла (Bluetooth отвалился вместе с севшим телефоном).
    static let staleAfter: Double = 12 * 3600

    static func step(from last: Sample?, to next: Sample) -> Step {
        guard next.accuracy >= 0, next.accuracy <= maxAccuracy else { return .skip }
        guard let last else { return .anchor }
        let elapsed = next.time - last.time
        guard elapsed > 0 else { return .skip }
        let meters = MapGeo.meters(from: GeoPoint(latitude: last.latitude, longitude: last.longitude),
                                   to: GeoPoint(latitude: next.latitude, longitude: next.longitude))
        guard meters >= minStep, meters / elapsed <= maxSpeed else { return .skip }
        return .move(meters)
    }

    /// Накопленный путь и опора для следующего шага.
    struct Progress: Equatable, Codable {
        var meters: Double = 0
        var last: Sample?

        mutating func add(_ sample: Sample) {
            switch TripMath.step(from: last, to: sample) {
            case .skip: break
            case .anchor: last = sample
            case .move(let step):
                meters += step
                last = sample
            }
        }
    }

    /// Сколько целых километров поездка добавляет к пробегу. Пробег целый, а
    /// поездки — нет: хвост меньше километра переносится на следующую, иначе
    /// десять поездок по 900 м не дали бы пробегу ничего.
    static func settle(meters: Double, carry: Double) -> (km: Int, carry: Double) {
        let total = max(0, meters) + max(0, carry)
        let km = Int(total / 1000)
        return (km, total - Double(km) * 1000)
    }

    /// Поездку удалили: сколько километров снять с пробега и что останется
    /// в счёте поездок. Снимается не больше, чем поездки в пробег добавили:
    /// после сверки с приборкой счёт обнулён, пробег задан человеком, и
    /// удаление поездки его уже не трогает.
    static func forget(meters: Double, trackedKm: Int, carry: Double)
        -> (km: Int, trackedKm: Int, carry: Double) {
        let total = Double(max(0, trackedKm)) * 1000 + max(0, carry)
        let rest = max(0, total - max(0, meters))
        let km = Int(rest / 1000)
        return (max(0, trackedKm) - km, km, rest - Double(km) * 1000)
    }

    /// Расстояние поездки поправили руками: на сколько километров сдвинуть
    /// пробег и что останется в счёте поездок. Считается от разницы, а не
    /// «удалить и записать заново»: после сверки с приборкой прибавка идёт в
    /// пробег, а убавка его не трогает — он уже задан человеком.
    static func adjust(from old: Double, to new: Double, trackedKm: Int, carry: Double)
        -> (km: Int, trackedKm: Int, carry: Double) {
        let delta = max(0, new) - max(0, old)
        guard delta < 0 else {
            let settled = settle(meters: delta, carry: carry)
            return (settled.km, max(0, trackedKm) + settled.km, settled.carry)
        }
        let back = forget(meters: -delta, trackedKm: trackedKm, carry: carry)
        return (-back.km, back.trackedKm, back.carry)
    }

    /// Длиннее 2 000 км за одну поездку — опечатка, а не поездка.
    static let maxTripKm: Double = 2_000

    /// Километры из поля правки: «3,9», «3.9», «12» → метры. `nil` — не
    /// число или не поездка: короче `minTrip` либо длиннее `maxTripKm`.
    static func meters(fromKm text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
            .filter { !$0.isWhitespace }
        guard let km = Double(cleaned), km.isFinite else { return nil }
        let meters = km * 1000
        return meters >= minTrip && km <= maxTripKm ? meters : nil
    }

    /// Расстояние для поля правки: «3,9», «12» — без единицы, с запятой.
    static func kmField(_ meters: Double) -> String {
        let km = (max(0, meters) / 100).rounded() / 10
        guard km != km.rounded() else { return String(Int(km)) }
        return String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",")
    }

    /// Расстояние идущей поездки. `MapGeo.distanceLabel` ниже 10 м не
    /// опускается — для места на карте это честно, а поездка, которая ещё
    /// стоит, показывала бы «10 м» (кадр 08.10.2026).
    static func liveDistance(_ meters: Double) -> String {
        meters < 10 ? "0\u{00A0}м" : MapGeo.distanceLabel(meters: meters)
    }

    static func isStale(startedAt: Double, now: Double) -> Bool {
        now - startedAt > staleAfter
    }

    /// Пробег на плитке: «≈ 56 412 км», пока в нём есть километры из
    /// поездок, не сверенные с приборкой, и «56 412 км» после сверки.
    static func odometerLabel(_ odometer: Int, trackedKm: Int) -> String {
        let value = "\(NumberFormat.grouped(odometer))\u{00A0}км"
        return trackedKm > 0 ? "≈\u{00A0}\(value)" : value
    }
}

/// Маршрут поездки — для карты на экране поездки (решение пользователя
/// 08.10.2026: «при нажатии на поездку выводи карту с маршрутом»). Лежит в
/// базе на телефоне рядом с поездкой и никуда не уходит.
enum TripTrack {
    /// Точку в маршрут пишем не чаще чем раз в 25 м: линии на карте этого
    /// хватает, а поездка в 50 км занимает 2 000 точек, не 6 000.
    static let minGap: Double = 25

    static func shouldAppend(_ point: GeoPoint, after last: GeoPoint?) -> Bool {
        guard let last else { return true }
        return MapGeo.meters(from: last, to: point) >= minGap
    }

    /// Восемь байт на точку: широта и долгота в миллионных долях градуса
    /// (11 см), целыми — так запись не зависит от формата чисел с точкой.
    static func encode(_ points: [GeoPoint]) -> Data {
        var data = Data(capacity: points.count * 8)
        for point in points {
            for value in [point.latitude, point.longitude] {
                let micro = Int32((value * 1_000_000).rounded()).littleEndian
                withUnsafeBytes(of: micro) { data.append(contentsOf: $0) }
            }
        }
        return data
    }

    /// Обрезанный хвост (запись оборвалась на полуслове) отбрасывается.
    static func decode(_ data: Data) -> [GeoPoint] {
        let bytes = [UInt8](data)
        func value(at offset: Int) -> Double {
            let raw = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
            return Double(Int32(bitPattern: raw)) / 1_000_000
        }
        return stride(from: 0, to: bytes.count - bytes.count % 8, by: 8).map {
            GeoPoint(latitude: value(at: $0), longitude: value(at: $0 + 4))
        }
    }

    /// Начало и конец маршрута — по ним ищутся адреса; `nil`, если точек
    /// меньше двух.
    static func endpoints(_ points: [GeoPoint]) -> (start: GeoPoint, end: GeoPoint)? {
        guard points.count > 1, let first = points.first, let last = points.last else { return nil }
        return (first, last)
    }

    /// Рамка маршрута для камеры карты; `nil`, если показывать нечего.
    static func bounds(_ points: [GeoPoint]) -> (southWest: GeoPoint, northEast: GeoPoint)? {
        guard let first = points.first else { return nil }
        var south = first.latitude, north = first.latitude
        var west = first.longitude, east = first.longitude
        for point in points.dropFirst() {
            south = min(south, point.latitude)
            north = max(north, point.latitude)
            west = min(west, point.longitude)
            east = max(east, point.longitude)
        }
        return (GeoPoint(latitude: south, longitude: west), GeoPoint(latitude: north, longitude: east))
    }

    /// Точка рисунка: координаты в кадре, pt, от левого верхнего угла.
    struct Spot: Equatable {
        var x: Double
        var y: Double
    }

    /// Маршрут в рамке кадра — для рисунка пути без карты: карта в карточке
    /// иногда не догружается (нет сети), и белый прямоугольник вместо неё
    /// выглядел поломкой (кадр пользователя 09.10.2026). Север вверху,
    /// долгота сжата по широте, пропорции сохранены, вокруг — поле `inset`.
    static func project(_ points: [GeoPoint], width: Double, height: Double,
                        inset: Double) -> [Spot] {
        guard let box = bounds(points), width > 2 * inset, height > 2 * inset else { return [] }
        let squeeze = cos((box.southWest.latitude + box.northEast.latitude) / 2 * .pi / 180)
        let spanX = (box.northEast.longitude - box.southWest.longitude) * squeeze
        let spanY = box.northEast.latitude - box.southWest.latitude
        let roomX = width - 2 * inset, roomY = height - 2 * inset
        // Маршрут из одной точки или по одной линии: делить на ноль нельзя,
        // а масштаб по второй оси всё равно годится.
        let scale = min(spanX > 0 ? roomX / spanX : .infinity, spanY > 0 ? roomY / spanY : .infinity)
        let usedX = scale.isFinite ? spanX * scale : 0
        let usedY = scale.isFinite ? spanY * scale : 0
        return points.map { point in
            let dx = scale.isFinite ? (point.longitude - box.southWest.longitude) * squeeze * scale : 0
            let dy = scale.isFinite ? (point.latitude - box.southWest.latitude) * scale : 0
            return Spot(x: inset + (roomX - usedX) / 2 + dx,
                        y: height - inset - (roomY - usedY) / 2 - dy)
        }
    }

    /// Подпись карточки поездки: «8 октября 2026, 21:16» — как в истории
    /// Делимобиля, с годом и временем начала.
    static func cardTitle(_ date: Date, calendar: Calendar) -> String {
        format(date, "d MMMM yyyy, HH:mm", calendar)
    }

    /// Заголовок экрана поездки: «Поездка 8 октября».
    static func sheetTitle(_ date: Date, calendar: Calendar) -> String {
        "Поездка " + format(date, "d MMMM", calendar)
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// «42 мин», «1 ч 5 мин»; короче минуты — «меньше минуты».
    static func durationLabel(seconds: Double) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes < 1 { return "меньше минуты" }
        if minutes < 60 { return "\(minutes)\u{00A0}мин" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60)\u{00A0}ч" : "\(minutes / 60)\u{00A0}ч \(rest)\u{00A0}мин"
    }

    /// Средняя скорость, км/ч. `nil` для поездки короче минуты: на таком
    /// отрезке она ничего не значит.
    static func speedLabel(meters: Double, seconds: Double) -> String? {
        guard seconds >= 60, meters > 0 else { return nil }
        return "\(Int((meters / seconds * 3.6).rounded()))\u{00A0}км/ч"
    }
}

/// Что приложению разрешено с геопозицией — глазами автопробега.
enum TripAccess: Equatable {
    case notAsked
    /// Только пока приложение открыто: поездку можно начать руками, а
    /// команда из фона подсчёт не запустит.
    case whenInUse
    case always
    case denied

    /// Запустит ли подсчёт команда, пока приложение закрыто.
    var worksFromCommand: Bool { self == .always }

    /// Значение строки «Доступ» в настройке автопробега.
    var status: String {
        switch self {
        case .notAsked: "Не задан"
        case .whenInUse: "При использовании"
        case .always: "Всегда"
        case .denied: "Запрещён"
        }
    }
}
