import AVFAudio
import CoreLocation
import CoreMotion
import SwiftData
import SwiftUI
import YandexMapsMobile

/// Выключатель геопозиции внутри приложения (просьба пользователя
/// 08.10.2026). Выключен — Beepy геопозицию не трогает вовсе: поездки не
/// считаются, на карте нет точки «я здесь». Системное разрешение при этом
/// остаётся каким было: отозвать его приложение не может, только человек в
/// «Настройках» — туда ведёт строка «Доступ» в разделе «Ещё».
enum LocationSwitch {
    static let key = "location.enabled"
    static var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

/// Выключатель автоопределения поездок. Включён — Beepy сам замечает, что
/// машина поехала (`TripAuto`), и «Команды» для этого не нужны.
enum AutoSwitch {
    static let key = "trip.auto"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }
}

/// Какой машине идут поездки без явного выбора: те, что Beepy начал сам, и
/// начатые кнопкой. Значение — имя машины для команд (`TripTracker.carID`).
enum TripCar {
    static let key = "trip.car"
    static var id: String? {
        UserDefaults.standard.string(forKey: key).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// База приложения одним объектом: её делят интерфейс и действия «Команд».
/// Действие запускается, когда окна ещё нет, и взять контейнер из окружения
/// SwiftUI ему неоткуда.
enum AppStore {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Car.self, ServiceRecord.self, ServiceWorkItem.self,
                                      Place.self, EngineCheck.self, EngineFinding.self, Trip.self)
        } catch {
            fatalError("База не открылась: \(error)")
        }
    }()
}

/// Автопробег: считает километры поездки и прибавляет их к пробегу машины.
///
/// Поездку начинает и заканчивает одно из трёх: сам Beepy (автоопределение,
/// решения — `TripAuto`), команда из автоматизации «Быстрых команд» по
/// Bluetooth машины (`TripIntents.swift`) или кнопка на экране «Ещё».
/// Расчёты пути — `TripMath`. Машина с привязанным Bluetooth получает
/// поездки, только пока он подключён (`TripLink`).
///
/// Автоопределение держится на двух сигналах системы, которые будят даже
/// закрытое приложение: выход из зоны вокруг места стоянки и «значимое
/// перемещение». Поэтому объект создаётся при каждом запуске
/// (`AppMVPApp.init`), а не только с экраном «Ещё».
///
/// Идущая поездка лежит в `UserDefaults` и переживает выгрузку приложения:
/// команда «Закончить» может прийти уже другому процессу. Маршрут пишется
/// отдельным файлом рядом с базой и с концом поездки переезжает в неё.
@MainActor
final class TripTracker: NSObject, ObservableObject {
    static let shared = TripTracker()

    struct Active: Equatable, Codable {
        /// Какой машине считать: то, что выбрано в команде. `nil` — решит
        /// `car(for:)` в конце поездки.
        var carID: String?
        var startedAt: Date
        var progress = TripMath.Progress()
        /// Есть только у поездки, которую Beepy начал сам: по нему она сама
        /// и закончится.
        var tail: TripAuto.Tail?
        /// Машина, чей Bluetooth подключён в этой поездке: пропал — поездка
        /// кончилась (`TripLink.lost`).
        var link: String?
        /// Когда Bluetooth привязанной поездки пропал; вернулся — снова `nil`.
        var lostAt: Double?
    }

    /// Чем закончилась поездка.
    enum Outcome: Equatable {
        /// Записана: километры ушли в пробег, поездка — в историю.
        case saved
        /// Короче `TripMath.minTrip` — в пробег и в историю не пошла.
        case tooShort
    }

    enum Failure: Error, Equatable {
        /// Команда пришла из фона, а геопозиция разрешена не «Всегда».
        case needsAlways
        /// Геопозиция выключена в самом приложении.
        case switchedOff
    }

    @Published private(set) var active: Active?
    @Published private(set) var access: TripAccess = .notAsked
    /// Доступ к датчикам движения закрыт: автоопределение работает по одной
    /// скорости и хуже отличает езду от ходьбы.
    @Published private(set) var motionDenied = false

    private let manager = CLLocationManager()
    private static let storageKey = "trip.active"
    private static let memoryKey = "trip.auto.memory"
    private static let spotPrefix = "beepy.spot."
    /// Как часто пересматривать пробу и идущую поездку, когда отсчётов нет:
    /// стоящий телефон их не шлёт, а закончить поездку надо.
    private static let tickSeconds: Double = 15

    private let motion = TripMotion()
    private var memory = TripAuto.Memory()
    /// Проба после пробуждения: поехали или ушли пешком.
    private var probe: TripAuto.Probe?
    private var probeTrack: [GeoPoint] = []
    /// Пробуждение ждёт ответа датчиков движения; второе в это время не нужно.
    private var waking = false
    /// Номер последнего пробуждения: перебитое узнаёт, что оно уже не главное.
    private var wakeID = 0
    /// «Значимое перемещение» ждёт, не выйдет ли приложение на экран.
    private var wandering = false
    /// Когда проба по «значимому перемещению» в последний раз ничего не нашла.
    private var lastMiss: Date?
    /// Отсчёты последних секунд идущей поездки — по ним видно, едем ли.
    private var drift = TripAuto.Drift()
    private static let wanderDelay: Double = 2
    private var ticker: Task<Void, Never>?

    /// Линия маршрута идущей поездки — для карты на экране поездки.
    private var track: [GeoPoint] = []
    /// Файл маршрута переписывается раз в столько новых точек: это полкилометра
    /// пути, которые теряются из линии (но не из километров), если процесс убьют.
    private static let trackFlushEvery = 20
    private static let trackURL = URL.applicationSupportDirectory.appending(path: "trip.track")
    /// После «При использовании» сразу просим «Всегда»: без него команда из
    /// фона ничего не запустит, а второй запрос система покажет сама.
    private var wantsAlways = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Реже, чем `TripMath.minStep`, отсчёты не нужны; чаще — только
        // будят процессор.
        manager.distanceFilter = TripMath.minStep
        manager.activityType = .automotiveNavigation
        // Сама система поездку на паузу не ставит: в пробке она сочла бы
        // стоянку концом пути, а возобновить подсчёт из фона нечем.
        manager.pausesLocationUpdatesAutomatically = false
        access = Self.access(for: manager.authorizationStatus)
        motion.onChange = { [weak self] in self?.tick() }
        // Смена выхода звука приходит, только пока приложение работает:
        // на экране, в пробе или в поездке. Будить закрытое она не умеет.
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.routeChanged() }
        }
        if let data = UserDefaults.standard.data(forKey: Self.memoryKey),
           let saved = try? JSONDecoder().decode(TripAuto.Memory.self, from: data) {
            memory = saved
        }

        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(Active.self, from: data) {
            active = saved
            track = (try? Data(contentsOf: Self.trackURL)).map(TripTrack.decode) ?? []
            if TripMath.isStale(startedAt: saved.startedAt.timeIntervalSinceReferenceDate,
                                now: Date.now.timeIntervalSinceReferenceDate) {
                finish()
            } else {
                listen()
                if saved.tail != nil { watch() }
            }
        }
        arm()
    }

    // MARK: - Команды

    /// Начать поездку с экрана: приложение открыто, хватит и «При использовании».
    func start(carID: String? = nil) {
        guard LocationSwitch.isOn else { return }
        if active != nil { finish() }
        // Человек начал сам — проба больше ничего не решает.
        probe = nil
        probeTrack = []
        stopWatching()
        active = Active(carID: carID, startedAt: .now)
        track = []
        try? FileManager.default.removeItem(at: Self.trackURL)
        persist()
        listen()
    }

    /// Начать поездку командой. Приложение при этом обычно закрыто, и без
    /// «Всегда» система не отдаст ему ни одного отсчёта — честнее отказать,
    /// чем молча «считать» ноль.
    func startFromCommand(carID: String?) throws {
        guard LocationSwitch.isOn else { throw Failure.switchedOff }
        access = Self.access(for: manager.authorizationStatus)
        guard access.worksFromCommand else { throw Failure.needsAlways }
        start(carID: carID)
    }

    /// Закончить поездку и прибавить километры к пробегу — по команде или
    /// кнопке: человек сказал «конец», и поездка пишется как есть.
    @discardableResult
    func finish() -> Outcome? {
        guard let closed = close(cut: false) else { return nil }
        return save(closed)
    }

    /// Поездка, снятая с подсчёта, но ещё не записанная.
    private struct Closed {
        var carID: String?
        var startedAt: Date
        var endedAt: Date
        var meters: Double
        var route: [GeoPoint]
        var end: GeoPoint?
        /// Начал её сам Beepy.
        var auto: Bool
        /// Шла с подключённым Bluetooth своей машины.
        var linked: Bool
        /// Весь насчитанный путь до обрезки — для журнала.
        var raw: Double
    }

    /// Остановить подсчёт и собрать итог. `cut` — обрезать по последнему
    /// месту, где точно ехали: так заканчивает поездку сам Beepy, и путь
    /// пешком от машины в пробег не идёт.
    private func close(cut: Bool) -> Closed? {
        guard let trip = active else { return nil }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        stopWatching()
        active = nil
        drift = TripAuto.Drift()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)

        var closed = Closed(carID: trip.carID, startedAt: trip.startedAt, endedAt: .now,
                            meters: trip.progress.meters, route: track,
                            // Последняя опора — конец пути: без неё линия обрывалась
                            // бы за 25 м до места, где машина встала.
                            end: trip.progress.last.map {
                                GeoPoint(latitude: $0.latitude, longitude: $0.longitude)
                            },
                            auto: trip.tail != nil, linked: trip.link != nil,
                            raw: trip.progress.meters)
        if cut, let tail = trip.tail {
            closed.meters = tail.meters
            closed.endedAt = Date(timeIntervalSinceReferenceDate: tail.moved)
            closed.route = Array(track.prefix(tail.points))
            closed.end = tail.place
        }
        if let end = closed.end, closed.route.last != end { closed.route.append(end) }
        track = []
        try? FileManager.default.removeItem(at: Self.trackURL)
        return closed
    }

    @discardableResult
    private func save(_ closed: Closed) -> Outcome {
        guard closed.meters >= TripMath.minTrip else {
            TripLog.note("trip short meters=\(Int(closed.meters))")
            return .tooShort
        }
        let context = AppStore.container.mainContext
        let fleet = Self.fleet(in: context)
        let car = Self.pick(closed.carID, from: fleet)
        let trip = Trip(startedAt: closed.startedAt, endedAt: closed.endedAt, meters: closed.meters,
                        car: car,
                        track: closed.route.count > 1 ? TripTrack.encode(closed.route) : nil)
        trip.auto = closed.auto
        context.insert(trip)
        if let car {
            let settled = TripMath.settle(meters: closed.meters, carry: car.tripCarry ?? 0)
            car.odometer += settled.km
            car.tripCarry = settled.carry
            car.trackedKm = (car.trackedKm ?? 0) + settled.km
        }
        try? context.save()
        TripSync.shared.changed()
        TripLog.note("trip end meters=\(Int(closed.meters)) raw=\(Int(closed.raw)) auto=\(closed.auto) audio=\(Self.audioRoute)")

        // Где закончили — там и стоит машина: вокруг этого места зона, из
        // которой начнётся следующая поездка. Память мест — машины по
        // умолчанию; приехали на другой — телефон не у неё, и зона там
        // начинала бы поездки не той машине (прогон 12.10.2026).
        if AutoSwitch.isOn, let end = closed.end {
            if car.map(Self.carID) == Self.pick(nil, from: fleet).map(Self.carID) {
                memory.park(at: end)
            } else {
                memory.atCar = false
            }
            saveMemory()
            syncRegions()
        }
        return .saved
    }

    /// Поездку, начатую самим Beepy, он сам и заканчивает — и перед записью
    /// проверяет: слишком короткую и ту, где датчики почти не видели езды,
    /// не пишет вовсе. Так прогулка, принятая за поездку, в историю и в
    /// пробег не попадает (кадр пользователя 09.10.2026: 1,6 км пешком).
    private func finishAuto() {
        guard let closed = close(cut: true) else { return }
        guard closed.meters >= TripAuto.autoMinTrip else {
            TripLog.note("trip dropped: short meters=\(Int(closed.meters)) raw=\(Int(closed.raw))")
            return
        }
        // Bluetooth своей машины был на связи — это она, датчики не спрашиваем.
        guard !closed.linked else {
            save(closed)
            return
        }
        Task {
            if let share = await motion.share(from: closed.startedAt, to: closed.endedAt),
               !TripAuto.wasDrive(share) {
                TripLog.note("trip dropped: no drive, drive=\(Int(share.drive)) foot=\(Int(share.foot)) of=\(Int(share.total)) meters=\(Int(closed.meters))")
                return
            }
            save(closed)
        }
    }

    /// Машина поездки: выбранная в команде; иначе выбранная на экране «Ещё»
    /// (`TripCar`); иначе та, что добавлена первой.
    static func car(for id: String?, in context: ModelContext) -> Car? {
        pick(id, from: fleet(in: context))
    }

    private static func fleet(in context: ModelContext) -> [Car] {
        (try? context.fetch(FetchDescriptor<Car>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    private static func pick(_ id: String?, from cars: [Car]) -> Car? {
        if let id = id ?? TripCar.id, let match = cars.first(where: { carID(of: $0) == id }) {
            return match
        }
        return cars.first
    }

    /// Привязка машины к Bluetooth; `nil` — не привязана.
    static func bond(of car: Car) -> TripLink.Bond? {
        guard car.bluetoothUID != nil || car.bluetoothName != nil else { return nil }
        return TripLink.Bond(carID: carID(of: car), uid: car.bluetoothUID ?? "",
                             name: car.bluetoothName ?? "")
    }

    /// Имя машины для команд: госномер, а у машины без номера — название.
    static func carID(of car: Car) -> String {
        car.plate.isEmpty ? car.name : car.plate
    }

    /// Выключатель геопозиции переключили. Выключили посреди поездки — она
    /// заканчивается с тем, что успела насчитать.
    func locationSwitched() {
        if !LocationSwitch.isOn, active != nil { finish() }
        arm()
    }

    // MARK: - Автоопределение

    /// Включить или выключить автоопределение — с экрана «Ещё» или из меню
    /// машины на главной. Одна дверь, чтобы порядок был один: выключатель,
    /// потом разрешения и сигналы.
    func setAuto(_ on: Bool) {
        guard on != AutoSwitch.isOn else { return }
        let defaults = UserDefaults.standard
        // Без геопозиции автоопределению не на что смотреть.
        if on, !LocationSwitch.isOn { defaults.set(true, forKey: LocationSwitch.key) }
        defaults.set(on, forKey: AutoSwitch.key)
        autoSwitched()
    }

    /// Чьи поездки считать, когда машин несколько. Места стоянки у каждой
    /// машины свои, поэтому со сменой машины память о них начинается заново:
    /// первая поездка засчитается откуда угодно.
    func setCar(_ id: String) {
        let current = Self.car(for: nil, in: AppStore.container.mainContext).map(Self.carID)
        UserDefaults.standard.set(id, forKey: TripCar.key)
        guard id != current, AutoSwitch.isOn else { return }
        memory = TripAuto.Memory()
        saveMemory()
        syncRegions()
        TripLog.note("car switched")
    }

    private func autoSwitched() {
        if AutoSwitch.isOn {
            // С чистого листа: прежние места могли устареть, а первая поездка
            // засчитается откуда угодно и покажет, где стоит машина.
            memory = TripAuto.Memory()
            saveMemory()
            // Зоны будят закрытое приложение только с доступом «Всегда».
            if access == .notAsked || access == .whenInUse { requestAccess() }
            motion.ask { [weak self] in self?.arm() }
            TripLog.note("auto on")
        } else {
            // Свою поездку Beepy закрывает сам — с той же проверкой, что всегда.
            if active?.tail != nil { finishAuto() }
            TripLog.note("auto off")
        }
        arm()
    }

    /// Поездку удалили: там, где она кончилась, машина не вставала.
    func forgetSpot(at point: GeoPoint) {
        let before = memory
        memory.forget(at: point)
        guard memory != before else { return }
        saveMemory()
        syncRegions()
        TripLog.note("spot forgotten, spots=\(memory.spots.count)")
    }

    /// Включить или выключить сигналы, которые будят приложение. Зовётся при
    /// запуске и при каждой смене выключателей и разрешения.
    private func arm() {
        motionDenied = motion.isDenied
        let regions = manager.monitoredRegions.filter { $0.identifier.hasPrefix(Self.spotPrefix) }
        guard AutoSwitch.isOn, LocationSwitch.isOn, access == .always else {
            manager.stopMonitoringSignificantLocationChanges()
            regions.forEach { manager.stopMonitoring(for: $0) }
            if probe != nil { endProbe() }
            return
        }
        manager.startMonitoringSignificantLocationChanges()
        syncRegions()
    }

    /// Зоны системы — ровно по списку мест в памяти.
    private func syncRegions() {
        guard AutoSwitch.isOn, access == .always else { return }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            // Зон на этом устройстве нет — остаётся «значимое перемещение».
            TripLog.note("zones unavailable")
            return
        }
        var wanted: [String: GeoPoint] = [:]
        for spot in memory.spots { wanted[Self.regionID(spot)] = spot }
        var have: Set<String> = []
        for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.spotPrefix) {
            if wanted[region.identifier] == nil {
                manager.stopMonitoring(for: region)
            } else {
                have.insert(region.identifier)
            }
        }
        for (id, spot) in wanted where !have.contains(id) {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude),
                radius: TripAuto.zoneRadius, identifier: id)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
        TripLog.note("zones want=\(wanted.count) had=\(have.count)")
    }

    /// Имя зоны — из координат места, до метра: то же место даёт то же имя,
    /// и зона не заводится второй раз.
    private static func regionID(_ spot: GeoPoint) -> String {
        spotPrefix + "\(Int((spot.latitude * 100_000).rounded())),\(Int((spot.longitude * 100_000).rounded()))"
    }

    private func saveMemory() {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        UserDefaults.standard.set(data, forKey: Self.memoryKey)
    }

    /// Систему что-то насторожило: телефон вышел из зоны или заметно
    /// переместился. Решаем, слушать ли геопозицию.
    private func wake(_ origin: TripAuto.Origin, zone: GeoPoint? = nil, fix: CLLocation? = nil) {
        guard AutoSwitch.isOn, LocationSwitch.isOn, access == .always,
              active == nil, probe == nil else { return }
        // Выход из зоны перебивает ещё не решённое «перемещение»: потерять
        // его нельзя, второго система не пришлёт.
        guard !waking || origin == .zone else { return }
        waking = true
        wakeID += 1
        let id = wakeID
        Task {
            let now = await motion.fresh()
            guard id == wakeID else { return }
            waking = false
            guard active == nil, probe == nil else { return }
            let sample = fix.map(Self.sample)
            let link = linkGate()
            guard TripAuto.shouldProbe(memory, origin: origin, fix: sample, motion: now,
                                       sinceMiss: lastMiss.map { Date.now.timeIntervalSince($0) },
                                       link: link) else {
                if let sample {
                    memory.seen(at: GeoPoint(latitude: sample.latitude, longitude: sample.longitude),
                                accuracy: sample.accuracy, riding: now?.mode == .drive)
                    saveMemory()
                }
                TripLog.note("wake \(origin.rawValue) skip motion=\(Self.label(now)) link=\(Self.label(link)) atCar=\(memory.atCar) spots=\(memory.spots.count)")
                return
            }
            probe = TripAuto.Probe(origin: origin, startedAt: Date.now.timeIntervalSinceReferenceDate,
                                   zone: zone)
            probeTrack = []
            listen()
            watch()
            TripLog.note("wake \(origin.rawValue) probe motion=\(Self.label(now)) link=\(Self.label(link)) atCar=\(memory.atCar) spots=\(memory.spots.count) audio=\(Self.audioRoute)")
        }
    }

    /// «Значимое перемещение» считается только из фона. Только что
    /// запущенному приложению система первым делом отдаёт старый отсчёт, и
    /// состояние у него в этот миг тоже «фон» — поэтому ждём пару секунд:
    /// открытое человеком приложение за это время выйдет на экран.
    private func wander(_ fix: CLLocation?) {
        guard !wandering else { return }
        wandering = true
        Task {
            try? await Task.sleep(for: .seconds(Self.wanderDelay))
            wandering = false
            guard UIApplication.shared.applicationState == .background else { return }
            wake(.wander, fix: fix)
        }
    }

    private func feedProbe(_ locations: [CLLocation]) {
        guard var current = probe else { return }
        for location in locations {
            let before = current.progress
            current.add(Self.sample(location))
            if current.progress != before, let last = current.progress.last {
                let point = GeoPoint(latitude: last.latitude, longitude: last.longitude)
                if TripTrack.shouldAppend(point, after: probeTrack.last) { probeTrack.append(point) }
            }
        }
        probe = current
        judge()
    }

    private func judge() {
        guard let current = probe else { return }
        let now = Date.now.timeIntervalSinceReferenceDate
        let sensed = motion.current
        let link = linkGate()
        switch TripAuto.verdict(current, motion: sensed, link: link, now: now) {
        case .wait:
            break
        case .drive:
            if current.first != nil {
                beginAuto(from: current, link: link)
            } else if now - current.startedAt >= TripAuto.probeWindow {
                // Едем, но спутников нет (гараж, тоннель): мерить нечем.
                TripLog.note("probe drive without fix, give up")
                endProbe()
            }
        case .away:
            if case .car = link {
                // Простояли пробу в своей машине — от неё не уходили.
                memory.atCar = true
            } else if current.origin == .zone {
                // Из зоны вышли и не поехали — значит, ушли от машины.
                memory.atCar = false
            } else if let last = current.progress.last {
                memory.seen(at: GeoPoint(latitude: last.latitude, longitude: last.longitude),
                            accuracy: last.accuracy, riding: false)
            }
            saveMemory()
            if current.origin == .wander { lastMiss = .now }
            TripLog.note("probe away motion=\(Self.label(sensed)) link=\(Self.label(link)) meters=\(Int(current.progress.meters)) net=\(Int(current.net)) atCar=\(memory.atCar)")
            endProbe()
        }
    }

    private func endProbe() {
        probe = nil
        probeTrack = []
        stopWatching()
        if active == nil {
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
        }
    }

    /// Проба решила «поехали»: её отсчёты становятся началом поездки.
    private func beginAuto(from current: TripAuto.Probe, link: TripLink.Gate) {
        guard let first = current.first, let last = current.progress.last else { return }
        var progress = current.progress
        var route = probeTrack
        let start = GeoPoint(latitude: first.latitude, longitude: first.longitude)
        // Подключена своя машина — поездка её, а не машины по умолчанию.
        let linked: String? = if case .car(let id) = link { id } else { nil }
        // Места стоянки в памяти — машины по умолчанию: прямая от них к
        // другой машине дорисовала бы путь, которого та не ехала.
        let ownsMemory = linked == nil
            || linked == Self.car(for: nil, in: AppStore.container.mainContext).map(Self.carID)
        let lead = ownsMemory
            ? TripAuto.lead(memory, origin: current.origin, zone: current.zone, first: start) : nil
        if let lead {
            progress.meters += lead.meters
            route.insert(lead.from, at: 0)
        }
        let place = GeoPoint(latitude: last.latitude, longitude: last.longitude)
        let now = Date.now.timeIntervalSinceReferenceDate
        active = Active(carID: linked, startedAt: Date(timeIntervalSinceReferenceDate: first.time),
                        progress: progress,
                        tail: TripAuto.Tail(moved: last.time, alive: now, meters: progress.meters,
                                            points: route.count, place: place),
                        link: linked)
        track = route
        drift = current.drift
        probe = nil
        probeTrack = []
        try? TripTrack.encode(track).write(to: Self.trackURL, options: .atomic)
        persist()
        // Отсчёты уже идут с пробы; поездка — уже с плашкой.
        manager.showsBackgroundLocationIndicator = true
        watch()
        TripLog.note("trip start origin=\(current.origin.rawValue) lead=\(Int(lead?.meters ?? 0)) net=\(Int(current.net)) run=\(current.driveRun) motion=\(Self.label(motion.current)) link=\(Self.label(link)) audio=\(Self.audioRoute)")
    }

    /// Пересмотр по времени: проба может кончиться, поездка — закончиться,
    /// даже когда отсчётов нет.
    private func tick() {
        if probe != nil {
            judge()
            return
        }
        guard var trip = active, var tail = trip.tail else {
            stopWatching()
            return
        }
        let now = Date.now.timeIntervalSinceReferenceDate
        let sensed = motion.current
        var changed = false
        switch linkGate() {
        case .car(let id) where trip.link == nil:
            // Своя машина подключилась уже в пути: поездка её.
            trip.link = id
            trip.carID = id
            tail.alive = now
            changed = true
            TripLog.note("trip linked late")
        case .car(let id) where trip.link == id:
            // Мотор работает, телефон в машине — стоим, но едем.
            tail.alive = now
            if trip.lostAt != nil { TripLog.note("link back") }
            trip.lostAt = nil
            changed = true
        default:
            if trip.link != nil, trip.lostAt == nil {
                trip.lostAt = now
                changed = true
                TripLog.note("link lost")
            }
        }
        if TripAuto.idling(sensed) {
            tail.alive = now
            changed = true
        }
        if changed {
            trip.tail = tail
            active = trip
            persist()
        }
        if TripAuto.shouldFinish(tail, motion: sensed, now: now)
            || TripLink.lost(since: trip.lostAt, now: now) {
            finishAuto()
        }
    }

    /// Выход звука сменился: подключился или пропал Bluetooth машины.
    private func routeChanged() {
        if probe != nil {
            judge()
        } else if active?.tail != nil {
            tick()
        } else if active == nil, case .car = linkGate() {
            // Приложение работает, а телефон сел в свою машину — посмотрим, поедет ли.
            wake(.link)
        }
    }

    /// Что сейчас говорит Bluetooth машины (`TripLink`). Машины читаются
    /// заново: их привязку меняют на экране «Ещё», а машину могут удалить.
    private func linkGate() -> TripLink.Gate {
        let cars = Self.fleet(in: AppStore.container.mainContext)
        let bonds = cars.compactMap(Self.bond)
        guard !bonds.isEmpty else { return .free }
        return TripLink.gate(connected: TripLink.connected(CarAudio.outputs, bonds: bonds),
                             defaultBound: Self.pick(nil, from: cars).flatMap(Self.bond) != nil)
    }

    private func watch() {
        motion.start()
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.tickSeconds))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    private func stopWatching() {
        ticker?.cancel()
        ticker = nil
        motion.stop()
    }

    private static func sample(_ location: CLLocation) -> TripMath.Sample {
        TripMath.Sample(latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        accuracy: location.horizontalAccuracy,
                        time: location.timestamp.timeIntervalSinceReferenceDate)
    }

    private static func label(_ motion: TripAuto.Motion?) -> String {
        guard let motion else { return "none" }
        return motion.mode.rawValue + (motion.sure ? "" : "?")
    }

    /// Без имени машины: журнал читают глазами, а имя в нём ни к чему.
    private static func label(_ link: TripLink.Gate) -> String {
        switch link {
        case .free: "free"
        case .car: "car"
        case .absent: "absent"
        }
    }

    /// Куда сейчас идёт звук телефона — для журнала. По записям настоящих
    /// поездок станет видно, отдаёт ли система закрытому приложению Bluetooth
    /// машины: это единственный признак, отличающий свою машину от такси.
    private static var audioRoute: String {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.isEmpty ? "-" : outputs.map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ",")
    }

    // MARK: - Разрешение

    /// Следующий шаг к «Всегда»: первый запрос, повышение или настройки.
    func requestAccess() {
        switch manager.authorizationStatus {
        case .notDetermined:
            wantsAlways = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    private static func access(for status: CLAuthorizationStatus) -> TripAccess {
        switch status {
        case .notDetermined: .notAsked
        case .authorizedWhenInUse: .whenInUse
        case .authorizedAlways: .always
        default: .denied
        }
    }

    // MARK: - Отсчёты

    private func listen(indicator: Bool = true) {
        // Фоновый режим `location` объявлен в Info.plist; без него эта
        // строка роняет приложение исключением.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = indicator
        manager.startUpdatingLocation()
    }

    private func persist() {
        guard let active, let data = try? JSONEncoder().encode(active) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func take(_ locations: [CLLocation]) {
        guard var trip = active else { return }
        let before = trip.progress
        for location in locations {
            let sample = Self.sample(location)
            let prior = trip.progress
            trip.progress.add(sample)
            guard trip.progress != prior else { continue }

            let point = GeoPoint(latitude: sample.latitude, longitude: sample.longitude)
            if TripTrack.shouldAppend(point, after: track.last) {
                track.append(point)
                if track.count % Self.trackFlushEvery == 0 {
                    try? TripTrack.encode(track).write(to: Self.trackURL, options: .atomic)
                }
            }
            // Поездка, которую начал Beepy: запоминаем последнее место, где
            // точно ехали, — по нему она закончится и обрежется.
            if trip.tail != nil, prior.last != nil {
                drift.add(sample)
                let linked = trip.link != nil && trip.lostAt == nil
                if TripAuto.rolling(drift, motion: motion.current, linked: linked) {
                    trip.tail = TripAuto.Tail(moved: sample.time,
                                              alive: max(sample.time, trip.tail?.alive ?? 0),
                                              meters: trip.progress.meters, points: track.count,
                                              place: point)
                }
            }
        }
        guard trip.progress != before else { return }
        active = trip
        persist()
        if trip.tail != nil { tick() }
    }
}

extension TripTracker: CLLocationManagerDelegate {
    // Менеджер создан на главном потоке и туда же шлёт события — поэтому
    // `assumeIsolated`, а не `Task`: порядок отсчётов терять нельзя.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            access = Self.access(for: manager.authorizationStatus)
            if wantsAlways, manager.authorizationStatus == .authorizedWhenInUse {
                wantsAlways = false
                manager.requestAlwaysAuthorization()
            }
            arm()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            if active != nil {
                take(locations)
            } else if probe != nil {
                feedProbe(locations)
            } else {
                // Ни поездки, ни пробы — значит, это «значимое перемещение».
                wander(locations.last)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        MainActor.assumeIsolated {
            guard region.identifier.hasPrefix(Self.spotPrefix) else { return }
            let center = (region as? CLCircularRegion)?.center
            TripLog.note("zone exit")
            wake(.zone, zone: center.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) })
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        MainActor.assumeIsolated {
            guard region.identifier.hasPrefix(Self.spotPrefix) else { return }
            // Вернулся в зону — снова у машины.
            memory.atCar = true
            saveMemory()
            TripLog.note("zone enter")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        MainActor.assumeIsolated {
            guard region.identifier.hasPrefix(Self.spotPrefix) else { return }
            TripLog.note("zone armed, monitored=\(manager.monitoredRegions.count)")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     monitoringDidFailFor region: CLRegion?, withError error: Error) {
        MainActor.assumeIsolated { TripLog.note("zone fail \(error.localizedDescription)") }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Отсчёта нет — поездка просто не растёт; следующий придёт сам.
    }
}

/// Датчики движения телефона: «идёт», «едет в машине», «лежит». Переводит
/// `CMMotionActivity` в `TripAuto.Motion`.
@MainActor
final class TripMotion {
    private let manager = CMMotionActivityManager()
    private var latest: TripAuto.Motion?
    private var running = false
    /// Датчики сказали новое — пробу или поездку стоит пересмотреть.
    var onChange: (() -> Void)?

    private static let unknown = TripAuto.Motion(mode: .unknown, sure: false)
    /// За сколько секунд назад спрашивать историю: шесть часов покрывают и
    /// долгую стоянку, и долгую прогулку без единой смены состояния.
    private static let lookBack: TimeInterval = 6 * 3600
    /// Дольше ответа истории не ждём: у пробуждения в фоне секунд десять.
    private static let patience: TimeInterval = 3

    /// Датчики есть и доступ выдан. В симуляторе их нет вовсе.
    var isUsable: Bool {
        CMMotionActivityManager.isActivityAvailable()
            && CMMotionActivityManager.authorizationStatus() == .authorized
    }

    var isDenied: Bool {
        guard CMMotionActivityManager.isActivityAvailable() else { return false }
        let status = CMMotionActivityManager.authorizationStatus()
        return status == .denied || status == .restricted
    }

    /// Что датчики говорят сейчас; `nil` — датчиков нет или доступ не выдан.
    var current: TripAuto.Motion? {
        isUsable ? latest ?? Self.unknown : nil
    }

    /// Первый запрос показывает системный вопрос о доступе. Зовётся, когда
    /// человек включает автоопределение: спрашивать из фона нельзя.
    func ask(then done: @escaping () -> Void) {
        guard CMMotionActivityManager.isActivityAvailable(),
              CMMotionActivityManager.authorizationStatus() == .notDetermined else {
            done()
            return
        }
        manager.queryActivityStarting(from: .now.addingTimeInterval(-60), to: .now, to: .main) { _, _ in
            MainActor.assumeIsolated { done() }
        }
    }

    /// Свежий ответ датчиков для только что разбуженного приложения: живых
    /// обновлений у него ещё не было, поэтому спрашиваем историю. История —
    /// это смены состояния: кто идёт уже десять минут, за последние три ни
    /// одной не оставил, и запрос на три минуты отвечал пустотой — отсюда
    /// `motion=unknown` у каждой пробы в журнале с телефона (09.10.2026).
    /// Поэтому окно длинное, а ответ — последняя запись: она и есть «сейчас».
    func fresh() async -> TripAuto.Motion? {
        guard isUsable else { return nil }
        return await withCheckedContinuation { continuation in
            var answered = false
            let answer: (TripAuto.Motion) -> Void = { value in
                guard !answered else { return }
                answered = true
                continuation.resume(returning: value)
            }
            manager.queryActivityStarting(from: .now.addingTimeInterval(-Self.lookBack), to: .now,
                                          to: .main) { [weak self] activities, _ in
                MainActor.assumeIsolated {
                    let value = activities?.last.map(Self.motion) ?? Self.unknown
                    self?.latest = value
                    answer(value)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.patience) {
                MainActor.assumeIsolated { answer(Self.unknown) }
            }
        }
    }

    /// Сколько секунд между двумя моментами датчики считали ездой и ходьбой
    /// — проверка поездки после её конца. `nil` — датчиков нет или история
    /// не ответила: судить не по чему.
    func share(from start: Date, to end: Date) async -> TripAuto.Share? {
        guard isUsable, end > start else { return nil }
        return await withCheckedContinuation { continuation in
            var answered = false
            let answer: (TripAuto.Share?) -> Void = { value in
                guard !answered else { return }
                answered = true
                continuation.resume(returning: value)
            }
            // Запас назад: состояние на начало поездки задала запись до неё.
            manager.queryActivityStarting(from: start.addingTimeInterval(-Self.lookBack), to: end,
                                          to: .main) { activities, _ in
                MainActor.assumeIsolated {
                    guard let activities, !activities.isEmpty else {
                        answer(nil)
                        return
                    }
                    var share = TripAuto.Share(drive: 0, foot: 0, total: end.timeIntervalSince(start))
                    for (index, activity) in activities.enumerated() {
                        let next = index + 1 < activities.count ? activities[index + 1].startDate : end
                        let seconds = min(next, end).timeIntervalSince(max(activity.startDate, start))
                        guard seconds > 0 else { continue }
                        switch Self.motion(activity).mode {
                        case .drive: share.drive += seconds
                        case .foot, .cycle: share.foot += seconds
                        case .still, .unknown: break
                        }
                    }
                    answer(share)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.patience) {
                MainActor.assumeIsolated { answer(nil) }
            }
        }
    }

    func start() {
        guard isUsable, !running else { return }
        running = true
        manager.startActivityUpdates(to: .main) { [weak self] activity in
            MainActor.assumeIsolated {
                guard let self, let activity else { return }
                let value = Self.motion(activity)
                guard value != self.latest else { return }
                self.latest = value
                self.onChange?()
            }
        }
    }

    func stop() {
        // Ответ датчиков живёт, пока идут обновления: к следующему
        // пробуждению он устареет, и решать по нему нельзя.
        latest = nil
        guard running else { return }
        running = false
        manager.stopActivityUpdates()
    }

    private static func motion(_ activity: CMMotionActivity) -> TripAuto.Motion {
        TripAuto.Motion(mode: TripAuto.mode(automotive: activity.automotive, cycling: activity.cycling,
                                            walking: activity.walking, running: activity.running,
                                            stationary: activity.stationary),
                        sure: activity.confidence != .low)
    }
}

/// Выходы звука телефона сейчас — для привязки Bluetooth машины (`TripLink`).
/// Система отдаёт их и закрытому приложению, разбуженному в фоне.
enum CarAudio {
    static var outputs: [TripLink.Port] {
        #if DEBUG
        if let fake = fakeOutputs { return fake }
        #endif
        return AVAudioSession.sharedInstance().currentRoute.outputs.map {
            TripLink.Port(kind: kind(of: $0.portType), uid: $0.uid, name: $0.portName)
        }
    }

    private static func kind(of type: AVAudioSession.Port) -> TripLink.Kind {
        switch type {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: .bluetooth
        case .carAudio: .carPlay
        default: .other
        }
    }

    #if DEBUG
    /// В симуляторе Bluetooth нет. Файл `fake-route` рядом с базой подменяет
    /// выходы для проверки: строка «bluetooth|идентификатор|имя» на выход,
    /// пустой файл — один динамик. Файла нет — выходы настоящие.
    private static var fakeOutputs: [TripLink.Port]? {
        let url = URL.applicationSupportDirectory.appending(path: "fake-route")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, let kind = TripLink.Kind(rawValue: parts[0]) else { return nil }
            return TripLink.Port(kind: kind, uid: parts[1], name: parts[2])
        }
    }
    #endif
}

/// Журнал автоопределения: что разбудило приложение и что оно решило.
/// Нужен, потому что проверить автоопределение можно только настоящей
/// поездкой, а смотреть в этот момент некому. Лежит на телефоне рядом с
/// базой, наружу не уходит; координат в нём нет.
enum TripLog {
    private static let url = URL.applicationSupportDirectory.appending(path: "trip-auto.log")
    /// Больше — старая половина отбрасывается.
    private static let limit = 256 * 1024

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func note(_ text: String) {
        let line = Data((stamp.string(from: .now) + " " + text + "\n").utf8)
        guard var data = try? Data(contentsOf: url) else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? line.write(to: url, options: .atomic)
            return
        }
        if data.count > limit { data = data.suffix(limit / 2) }
        data.append(line)
        try? data.write(to: url, options: .atomic)
    }
}

/// Адрес точки — геокодером Яндекса. Наружу уходят только две точки
/// поездки, начало и конец, и только чтобы подписать их на экране поездки.
@MainActor
final class TripGeocoder {
    static let shared = TripGeocoder()

    private lazy var manager = YMKSearchFactory.instance().createSearchManager(with: .combined)
    /// Сессии SDK держит слабо: без ссылки запрос отменяется, не ответив.
    private var sessions: [UUID: YMKSearchSession] = [:]

    /// «улица Остоженка, 12» или `nil`: нет ключа, сети или дома рядом.
    func address(at point: GeoPoint) async -> String? {
        guard MapKitKey.isConfigured else { return nil }
        let options = YMKSearchOptions()
        options.searchTypes = .geo
        options.resultPageSize = 1
        return await withCheckedContinuation { continuation in
            let id = UUID()
            sessions[id] = manager.submit(
                with: YMKPoint(latitude: point.latitude, longitude: point.longitude),
                // 17 — масштаб домов: на меньшем геокодер отвечает улицей.
                zoom: 17,
                searchOptions: options
            ) { [weak self] response, _ in
                self?.sessions[id] = nil
                continuation.resume(returning: response?.collection.children.first?.obj?.name)
            }
        }
    }
}
