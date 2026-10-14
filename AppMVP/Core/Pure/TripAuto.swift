import Foundation

/// Автоопределение поездки: Beepy сам замечает, что машина поехала, без
/// «Команд» (решение пользователя 08.10.2026).
///
/// Конец каждой поездки — место, где встала машина. Вокруг таких мест
/// система держит зоны и будит приложение, когда телефон из зоны выходит.
/// Проснувшись, `TripTracker` недолго слушает геопозицию и датчики движения —
/// это «проба». Проба решает: поехали или ушли пешком. Поехали — поездка
/// считается сама и сама заканчивается, когда свидетельств езды нет дольше
/// порога.
///
/// Само по себе это не отличает свою машину от такси, уехавшего от места,
/// где машина стоит или стояла раньше. Отличает привязка Bluetooth машины
/// (`TripLink`); без неё лишнюю поездку можно удалить (`TripMath.forget`).
///
/// Здесь — решения. Геопозиция, датчики и зоны живут в `TripTracker`.
enum TripAuto {
    // MARK: - Пороги

    /// Радиус зоны вокруг места, где встала машина. Меньше ста метров система
    /// держит плохо, больше — в зону попадает чужая остановка.
    static let zoneRadius: Double = 150
    /// Места ближе 100 м — одно место: тот же двор, та же парковка.
    static let mergeRadius: Double = 100
    /// Сколько последних мест помнить. Машина возвращается к дому и работе:
    /// поездку пропустили — следующая от знакомого места подхватится.
    static let maxSpots = 6

    /// Окно, по которому меряется чистое смещение: от первого отсчёта окна
    /// до последнего по прямой. Шум геопозиции раздувает пройденный путь, а
    /// не смещение — скачок туда и обратно в нём гасится. По пути пешеход на
    /// привокзальной площади «ехал» 9,6 км/ч, и два шага-скачка подряд
    /// начинали ему поездку (журнал с телефона, 09.10.2026).
    static let driftSpan: Double = 40
    /// Короче 20 секунд смещение ничего не значит: его делает один скачок.
    static let driftMin: Double = 20
    /// Смещение от 5 м/с (18 км/ч) — уже не пешком. Велосипед сойдёт за
    /// машину, если датчики движения молчат: отличить больше нечем.
    static let driveDrift: Double = 5
    /// Столько отсчётов подряд со смещением не ниже `driveDrift` — едем.
    static let driveSteps = 2
    /// И от начала пробы по прямой должно набраться столько метров.
    static let minNet: Double = 150

    /// Минуту ни с места — слушать дальше незачем. Раньше проба стояла все
    /// три минуты с плашкой геопозиции, пока телефон лежал на столе.
    static let idleProbe: Double = 60
    static let idleNet: Double = 30
    /// После пробы, которая ничего не нашла, «значимому перемещению» десять
    /// минут не верим: у вокзала оно приходило каждые шесть минут.
    static let wanderCooldown: Double = 600

    /// Поездку, начатую самим Beepy, короче полукилометра не записываем.
    static let autoMinTrip: Double = 500
    /// Доля времени «в машине» по датчикам, ниже которой поездка — не
    /// поездка: прогулка, велосипед, самокат.
    static let driveShare: Double = 0.25

    /// Датчики уверенно говорят «идёт» — столько слушаем и сдаёмся.
    static let footProbe: Double = 45
    /// Дольше трёх минут пробу не держим: это геопозиция в фоне.
    static let probeWindow: Double = 180

    /// Пять минут без свидетельств езды — приехали. Долгая пробка разрежет
    /// поездку надвое, но километры не потеряются: следующая начнётся с
    /// прямой от этого же места.
    static let stopGap: Double = 300
    /// Датчики уверенно говорят «идёт» — ждать пять минут незачем.
    static let footGap: Double = 90
    /// Датчики могут залипнуть на «в машине». Двадцать минут без единого шага
    /// — конец, что бы они ни говорили.
    static let idleCap: Double = 1_200

    /// В своей машине (Bluetooth на связи) едем уже от 1,5 м/с чистого
    /// смещения: пробка ползёт медленнее 18 км/ч, а дрожание GPS на стоянке
    /// за 20–40 секунд столько не набирает.
    static let linkedDrift: Double = 1.5

    /// Дальше 5 км от места стоянки прямую не дорисовываем: машина, скорее
    /// всего, стояла не там.
    static let maxLead: Double = 5_000

    // MARK: - Датчики движения

    /// Чем занят телефон по датчикам движения.
    enum Mode: String, Codable, Equatable {
        case drive
        case foot
        case cycle
        /// Лежит неподвижно.
        case still
        case unknown
    }

    struct Motion: Equatable, Codable {
        var mode: Mode
        /// Уверенность датчиков не ниже средней.
        var sure: Bool

        /// Точно не в машине: идёт, едет на велосипеде или лежит.
        var surelyNotDriving: Bool {
            sure && (mode == .foot || mode == .cycle || mode == .still)
        }
    }

    /// Флаги `CMMotionActivity` → режим. В машине на светофоре стоят сразу
    /// «автомобиль» и «неподвижен» — это всё ещё машина.
    static func mode(automotive: Bool, cycling: Bool, walking: Bool, running: Bool,
                     stationary: Bool) -> Mode {
        if automotive { return .drive }
        if cycling { return .cycle }
        if walking || running { return .foot }
        if stationary { return .still }
        return .unknown
    }

    // MARK: - Память

    /// Что автоопределение помнит между запусками.
    struct Memory: Equatable, Codable {
        /// Места, где вставала машина; последнее — первым. Пусто — ещё ни
        /// одной поездки, и первая засчитается откуда угодно.
        var spots: [GeoPoint] = []
        /// Телефон не уходил пешком из зоны, в которой его видели последний раз.
        var atCar = false

        func nearest(to point: GeoPoint) -> GeoPoint? {
            spots.min { MapGeo.meters(from: $0, to: point) < MapGeo.meters(from: $1, to: point) }
        }

        /// Машина встала здесь: место уходит в начало списка, соседние с ним
        /// (тот же двор) заменяются.
        mutating func park(at point: GeoPoint) {
            spots.removeAll { MapGeo.meters(from: $0, to: point) <= TripAuto.mergeRadius }
            spots.insert(point, at: 0)
            if spots.count > TripAuto.maxSpots {
                spots.removeLast(spots.count - TripAuto.maxSpots)
            }
            atCar = true
        }

        /// Поездку, которая кончилась здесь, удалили: это была не машина, и
        /// места стоянки тут нет. Где сейчас телефон, неизвестно — считаем,
        /// что не у машины: выход из настоящей зоны всё равно засчитается.
        mutating func forget(at point: GeoPoint) {
            let before = spots.count
            spots.removeAll { MapGeo.meters(from: $0, to: point) <= TripAuto.mergeRadius }
            if spots.count != before { atCar = false }
        }

        /// Телефон замечен в точке. Точно внутри зоны — он у машины; точно
        /// снаружи всех и не едет — ушёл. Грубый отсчёт, по которому не
        /// понять, ничего не меняет.
        mutating func seen(at point: GeoPoint, accuracy: Double, riding: Bool) {
            guard accuracy >= 0, !spots.isEmpty else { return }
            let distances = spots.map { MapGeo.meters(from: $0, to: point) }
            if distances.contains(where: { $0 + accuracy <= TripAuto.zoneRadius }) {
                atCar = true
            } else if !riding, distances.allSatisfy({ $0 - accuracy > TripAuto.zoneRadius }) {
                atCar = false
            }
        }
    }

    /// Что разбудило приложение.
    enum Origin: String, Codable, Equatable {
        /// Телефон вышел из зоны вокруг машины.
        case zone
        /// Система заметила большое перемещение. Запасной сигнал: выход из
        /// зоны может опоздать или не прийти вовсе.
        case wander
        /// Подключился Bluetooth привязанной машины, пока приложение работало.
        case link
    }

    /// Слушать ли геопозицию после пробуждения. `fix` — отсчёт, с которым
    /// пришёл запасной сигнал; `motion` — `nil`, когда датчиков движения нет;
    /// `sinceMiss` — сколько секунд назад проба по такому же сигналу ничего
    /// не нашла; `link` — что говорит Bluetooth машины.
    static func shouldProbe(_ memory: Memory, origin: Origin, fix: TripMath.Sample?,
                            motion: Motion?, sinceMiss: Double? = nil,
                            link: TripLink.Gate = .free) -> Bool {
        switch link {
        case .car:
            // Телефон в своей машине — слушаем, что бы ни было раньше.
            return true
        case .absent:
            // Своя машина молчит. Перемещение — такси или прогулка; выход из
            // зоны стоит минуты ожидания: Bluetooth мог не успеть.
            return origin == .zone
        case .free:
            break
        }
        if origin != .wander { return true }
        if motion?.surelyNotDriving == true { return false }
        let driving = motion?.sure == true && motion?.mode == .drive
        // Прошлая проба ничего не нашла — подряд не слушаем, пока датчики
        // сами не скажут «в машине».
        if let sinceMiss, sinceMiss < wanderCooldown, !driving { return false }
        // Мест ещё нет — первая поездка засчитывается откуда угодно.
        if memory.spots.isEmpty { return true }
        // Телефон ушёл от машины пешком: всё, что едет дальше, — не она.
        guard memory.atCar else { return false }
        if let motion, motion.sure, motion.mode == .drive { return true }
        guard let fix, fix.accuracy >= 0 else { return true }
        // Возможно, ещё в зоне — тогда дождёмся выхода из неё.
        let point = GeoPoint(latitude: fix.latitude, longitude: fix.longitude)
        return memory.spots.allSatisfy {
            MapGeo.meters(from: $0, to: point) - fix.accuracy > zoneRadius
        }
    }

    // MARK: - Чистое смещение

    /// Отсчёты за последние `driftSpan` секунд — по ним видно, едем ли.
    struct Drift: Equatable, Codable {
        var samples: [TripMath.Sample] = []

        mutating func add(_ sample: TripMath.Sample) {
            samples.append(sample)
            // Самый старый отсчёт остаётся, пока без него окно не короче нужного.
            while samples.count > 2, sample.time - samples[1].time >= TripAuto.driftSpan {
                samples.removeFirst()
            }
        }

        /// Скорость смещения по прямой, м/с; `nil`, пока отсчёты не
        /// разошлись на `driftMin` секунд.
        var speed: Double? {
            guard let first = samples.first, let last = samples.last,
                  last.time - first.time >= TripAuto.driftMin else { return nil }
            let meters = MapGeo.meters(
                from: GeoPoint(latitude: first.latitude, longitude: first.longitude),
                to: GeoPoint(latitude: last.latitude, longitude: last.longitude))
            return meters / (last.time - first.time)
        }

        var isDriving: Bool { (speed ?? 0) >= TripAuto.driveDrift }
    }

    // MARK: - Проба

    /// Проба: короткое прослушивание после пробуждения.
    struct Probe: Equatable, Codable {
        var origin: Origin
        var startedAt: Double
        /// Центр зоны, из которой вышли.
        var zone: GeoPoint?
        var first: TripMath.Sample?
        var progress = TripMath.Progress()
        var drift = Drift()
        /// Сколько отсчётов подряд смещение не ниже `driveDrift`.
        var driveRun = 0

        init(origin: Origin, startedAt: Double, zone: GeoPoint? = nil) {
            self.origin = origin
            self.startedAt = startedAt
            self.zone = zone
        }

        mutating func add(_ sample: TripMath.Sample) {
            switch TripMath.step(from: progress.last, to: sample) {
            case .skip:
                return
            case .anchor:
                first = sample
            case .move:
                break
            }
            progress.add(sample)
            drift.add(sample)
            driveRun = drift.isDriving ? driveRun + 1 : 0
        }

        /// Сколько метров по прямой от первого отсчёта пробы до последнего.
        var net: Double {
            guard let first, let last = progress.last else { return 0 }
            return MapGeo.meters(
                from: GeoPoint(latitude: first.latitude, longitude: first.longitude),
                to: GeoPoint(latitude: last.latitude, longitude: last.longitude))
        }
    }

    enum Verdict: Equatable {
        /// Поехали — начинаем поездку.
        case drive
        /// Ушли пешком или никуда не делись.
        case away
        /// Пока непонятно.
        case wait
    }

    static func verdict(_ probe: Probe, motion: Motion?, link: TripLink.Gate = .free,
                        now: Double) -> Verdict {
        let elapsed = now - probe.startedAt
        switch link {
        case .car:
            // В своей машине «идёт» у датчиков — ошибка первых секунд, а
            // стоянка с мотором — ещё не повод сдаться: ждём, пока поедет.
            if let motion, motion.sure, motion.mode == .drive { return .drive }
            if probe.net >= minNet { return .drive }
            return elapsed >= probeWindow ? .away : .wait
        case .absent:
            // Поехать без своей машины нельзя: ждём, не подключится ли она.
            return elapsed >= TripLink.linkWait ? .away : .wait
        case .free:
            break
        }
        if let motion, motion.sure, motion.mode == .drive { return .drive }
        // Датчики уверены, что человек идёт или едет на велосипеде, —
        // геопозиции не верим: «быстрые» отсчёты у пешехода — скачки, а не
        // скорость. «Лежит» сюда не входит: телефон в держателе лежит и в
        // едущей машине, и смещение это покажет.
        let onFoot = motion?.sure == true && (motion?.mode == .foot || motion?.mode == .cycle)
        if !onFoot, probe.driveRun >= driveSteps, probe.net >= minNet { return .drive }

        if onFoot, elapsed >= footProbe { return .away }
        if elapsed >= idleProbe, probe.net < idleNet, motion?.mode != .drive { return .away }
        guard elapsed >= probeWindow else { return .wait }
        // Окно вышло. Неуверенное «в машине» — довод за поездку, если телефон
        // при этом и правда уехал: пропущенная обходится дороже лишней.
        return motion?.mode == .drive && probe.net >= minNet ? .drive : .away
    }

    /// Прямая от места стоянки до первого отсчёта: пока система будила
    /// приложение, машина уже проехала сотни метров.
    struct Lead: Equatable {
        var from: GeoPoint
        var meters: Double
    }

    static func lead(_ memory: Memory, origin: Origin, zone: GeoPoint?, first: GeoPoint) -> Lead? {
        let from = origin == .zone ? zone ?? memory.nearest(to: first) : memory.nearest(to: first)
        guard let from else { return nil }
        let meters = MapGeo.meters(from: from, to: first)
        return meters <= maxLead ? Lead(from: from, meters: meters) : nil
    }

    // MARK: - Конец поездки

    /// Последнее место, где точно ехали. По нему поездка обрезается в конце:
    /// путь пешком от машины в пробег не идёт.
    struct Tail: Equatable, Codable {
        /// Когда был последний шаг езды — это и есть время, когда встали.
        var moved: Double
        /// Последнее свидетельство езды: шаг или «в машине» от датчиков, пока
        /// стоим на светофоре.
        var alive: Double
        /// Путь и число точек маршрута на момент последнего шага езды.
        var meters: Double
        var points: Int
        var place: GeoPoint
    }

    /// Едем ли на этом шаге. Датчики уверены в обратном — нет, что бы ни
    /// показывала геопозиция; говорят «в машине» — да; молчат — решает
    /// чистое смещение.
    ///
    /// `linked` — Bluetooth своей машины на связи. Тогда «идёт» у датчиков
    /// не довод: телефон в машине. Без этого исключения поездка обрезалась
    /// по точке старта — датчики весь путь говорили «пешком», и 20 минут
    /// езды записывались как 173 м (журнал с телефона, 13–14.10.2026).
    static func rolling(_ drift: Drift, motion: Motion?, linked: Bool = false) -> Bool {
        if linked {
            if motion?.mode == .drive { return true }
            guard let speed = drift.speed else { return true }
            return speed >= linkedDrift
        }
        if let motion {
            if motion.sure, motion.mode == .foot || motion.mode == .cycle { return false }
            if motion.mode == .drive { return true }
        }
        return drift.isDriving
    }

    /// Стоим, но в машине: светофор, пробка.
    static func idling(_ motion: Motion?) -> Bool {
        motion?.sure == true && motion?.mode == .drive
    }

    static func shouldFinish(_ tail: Tail, motion: Motion?, now: Double) -> Bool {
        if now - tail.moved >= idleCap { return true }
        let onFoot = motion?.sure == true && motion?.mode == .foot
        return now - tail.alive >= (onFoot ? footGap : stopGap)
    }

    // MARK: - Проверка после поездки

    /// Сколько секунд поездки датчики считали ездой и ходьбой.
    struct Share: Equatable {
        var drive: Double
        var foot: Double
        var total: Double
    }

    /// Была ли это поездка на машине — по истории датчиков движения за её
    /// время. Ехали меньше четверти времени — не была: прогулка, велосипед,
    /// самокат. Поездка, начатая и законченная по одной геопозиции, проходит
    /// эту проверку последней.
    static func wasDrive(_ share: Share) -> Bool {
        guard share.total > 0 else { return true }
        return share.drive >= share.total * driveShare
    }
}
