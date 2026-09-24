import CoreLocation
import SwiftData
import SwiftUI
import YandexMapsMobile

/// Точка на карте в терминах интерфейса. Одинаково описывает и найденное у
/// Яндекса, и добавленное пользователем: экрану всё равно, откуда место, а
/// различие нужно только для значка и для того, можно ли место удалить.
struct MapPin: Identifiable, Equatable {
    enum Source: Equatable {
        case found
        case saved(PersistentIdentifier)
    }

    let id: String
    let title: String
    let subtitle: String?
    let kind: PlaceKind
    let latitude: Double
    let longitude: Double
    let source: Source
    /// Телефон организации, если поиск его отдал. `var` с умолчанием, а не
    /// `let`: так почленный инициализатор остаётся прежним для тех, у кого
    /// телефона нет вовсе, — своя точка на карте телефона не имеет.
    var phone: String?
    /// Как ещё записаться: онлайн-запись, мессенджеры, сайт — из карточки
    /// организации у Яндекса. В базу не сохраняется: избранное хранит только
    /// телефон, а ссылки приходят заново с каждым поиском.
    var contacts: [ContactLink] = []

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isSaved: Bool {
        if case .saved = source { return true }
        return false
    }

    /// Координаты для чистого слоя: расстояние и сверка мест считаются там.
    var point: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }
}

extension MapPin {
    /// Точка из сохранённого места.
    ///
    /// Идентификатор собирается здесь, в одном месте: список и карта выбирают
    /// одну и ту же точку по строке, и разойдись эти строки — выбор из списка
    /// перестал бы совпадать с выбором по тапу, причём молча.
    init(place: Place) {
        self.init(id: "saved-\(place.persistentModelID.hashValue)",
                  title: place.title,
                  subtitle: place.note,
                  kind: place.kind,
                  latitude: place.latitude,
                  longitude: place.longitude,
                  source: .saved(place.persistentModelID),
                  phone: place.phone)
    }
}

/// Заготовка места, которую пользователь ставит долгим нажатием.
struct PlaceDraft: Identifiable, Equatable {
    let id = UUID()
    let latitude: Double
    let longitude: Double
}

/// Всё, что раздел «Карта» знает про Яндекс: карта, поиск мест, маршрут и
/// передача маршрута в приложение Яндекс Карт.
///
/// Одним объектом, а не тремя, намеренно. SDK здесь объектно-графовый и
/// требовательный к владению: слушатели он держит **слабо**, сессии поиска и
/// маршрута отменяются, как только на них не осталось сильной ссылки. Разложить
/// это по нескольким мелким типам значит развести владение по местам, где его
/// легко потерять, — а потеря молчаливая: карта просто перестаёт отвечать.
///
/// Не помечен `@MainActor` сознательно: класс подписывается на протоколы SDK и
/// CoreLocation, чьи требования не изолированы. Все вызовы и так приходят на
/// главную очередь — и слушатели карты, и делегат геопозиции.
final class MapController: NSObject, ObservableObject {
    // MARK: Состояние для интерфейса

    /// Какие типы показывать. Меняется чипами наверху.
    @Published var activeKinds: Set<PlaceKind> = Set(PlaceKind.allCases) {
        didSet {
            guard activeKinds != oldValue else { return }
            carparks?.setVisibleWithOn(activeKinds.contains(.parking))
            redraw()
            search()
        }
    }
    @Published private(set) var found: [MapPin] = []
    @Published var selected: MapPin?
    @Published private(set) var isSearching = false
    @Published var draft: PlaceDraft?
    @Published var message: String?
    /// Есть ли разрешение и позиция. Без неё маршрут строить не от чего.
    @Published private(set) var hasLocation = false
    /// Яндекс отверг ключ. Отдельным состоянием, а не текстом ошибки: без
    /// ключа карта показывает пустую сетку и выглядит сломанной, хотя сломан
    /// не код. Определяется по типу ошибки из SDK, а не по её тексту.
    @Published private(set) var keyRejected = false
    /// Идёт поиск ближайшего сервиса для записи — кнопка «Записаться» на
    /// главной привела сюда.
    @Published private(set) var isFindingService = false
    /// Точка, которую нашли как ближайший сервис. Карточка подписывает её
    /// «Ближайший сервис», пока выбрана именно она.
    @Published private(set) var nearestServiceID: String?

    /// Сохранённые места. Их держит `@Query` на экране и передаёт сюда:
    /// контроллеру не нужен доступ к базе, ему нужен только список.
    private(set) var saved: [Place] = []

    // MARK: Владение объектами SDK

    private weak var map: YMKMap?
    private var placemarks: YMKMapObjectCollection?
    /// Готовый слой парковок Яндекса: платные и бесплатные зоны с разметкой,
    /// те же, что в Яндекс Картах. Им, а не поиском «парковка», показываются
    /// парковки: поиск находил организации-парковки точками, а у Яндекса
    /// парковка — это участок улицы с ценой, и точкой её не описать.
    private var carparks: YMKCarparksLayer?
    private var userLayer: YMKUserLocationLayer?

    /// Сессии держим сильно: в SDK они отменяются, как только на них не
    /// осталось ссылки, и запрос молча не доходит.
    private var searchSessions: [PlaceKind: YMKSearchSession] = [:]
    /// Сторож на зависший поиск. При отказе по ключу или на мёртвой сети SDK
    /// уходит в бесконечные повторы и обработчик не вызывает вовсе — без
    /// сторожа индикатор крутился бы всегда.
    private var searchWatchdog: DispatchWorkItem?
    /// Отдельно от `searchSessions`: смена фильтров перезапускает тот поиск
    /// и отменила бы этот.
    private var nearestSession: YMKSearchSession?
    /// Ближайший сервис попросили раньше, чем пришла геопозиция. Искать
    /// будем с первой же точкой — от случайной области карты «ближайший»
    /// ничего не значит.
    private var wantsNearestService = false
    private lazy var searchManager =
        YMKSearchFactory.instance().createSearchManager(with: .combined)

    private let location = CLLocationManager()
    /// Где пользователь. Наблюдаемое, потому что от него зависят подписи
    /// расстояний в списке; приходит раз в несколько секунд, а не на каждом
    /// кадре, — перерисовку это не разгоняет.
    @Published private(set) var here: CLLocationCoordinate2D?
    /// Камера прыгает к пользователю только один раз за открытие экрана:
    /// иначе каждое уточнение позиции утаскивало бы карту у него из-под пальца.
    private var didCenter = false

    // MARK: - Жизненный цикл

    /// Вызывается обёрткой, когда карта создана.
    func attach(to mapView: YMKMapView) {
        let map = mapView.mapWindow.map
        self.map = map

        // Тёмная карта — лейтмотив приложения. У Яндекса это встроенный
        // ночной режим самой карты, а не наш оверлей: подписи и дороги
        // остаются читаемыми, чего фильтром поверх не добиться.
        map.isNightModeEnabled = true

        placemarks = map.mapObjects.add()

        // Слушатели SDK хранит слабо — живыми их держит сам контроллер,
        // который лежит в `@StateObject` экрана.
        placemarks?.addTapListener(with: self)
        map.addInputListener(with: self)

        let layer = YMKMapKit.sharedInstance()
            .createUserLocationLayer(with: mapView.mapWindow)
        layer.setVisibleWithOn(true)
        userLayer = layer

        let carparks = YMKDirectionsFactory.instance()
            .createCarparksLayer(with: mapView.mapWindow)
        carparks.setVisibleWithOn(activeKinds.contains(.parking))
        self.carparks = carparks

        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyHundredMeters
        requestLocation()

        redraw()
    }

    func detach() {
        searchWatchdog?.cancel()
        searchSessions.values.forEach { $0.cancel() }
        searchSessions.removeAll()
        nearestSession?.cancel()
        nearestSession = nil
        isFindingService = false
        location.stopUpdatingLocation()
        // Карту не отпускаем: ссылка на неё и так слабая, а системный
        // `TabView` на iOS 26 вкладку не пересоздаёт — `makeUIView` второй
        // раз не придёт, и после возврата на вкладку контроллер остался бы
        // без карты: ни поиска, ни камеры.
    }

    /// Вкладку показали снова — геопозиция нужна опять.
    func resume() {
        requestLocation()
    }

    func update(saved places: [Place]) {
        saved = places
        redraw()
    }

    private func requestLocation() {
        switch location.authorizationStatus {
        case .notDetermined: location.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: location.startUpdatingLocation()
        default: hasLocation = false
        }
    }

    // MARK: - Поиск мест

    /// Ищет активные типы в том куске карты, который сейчас видно.
    ///
    /// По видимой области, а не по радиусу от пользователя: человек отодвинул
    /// карту в соседний район именно затем, чтобы посмотреть, что там, — и
    /// поиск вокруг его собственной точки в этот момент бесполезен.
    func search() {
        // Парковки не ищутся: их рисует слой Яндекса, см. `carparks`.
        let kinds = activeKinds.subtracting([.parking])
        guard let map, !kinds.isEmpty else {
            if kinds.isEmpty { found = []; redraw() }
            return
        }

        let region = map.visibleRegion
        let box = YMKBoundingBox(southWest: region.bottomLeft, northEast: region.topRight)
        let geometry = YMKGeometry(boundingBox: box)

        let options = YMKSearchOptions()
        options.searchTypes = .biz
        options.resultPageSize = 32
        if let here { options.userPosition = YMKPoint(latitude: here.latitude,
                                                      longitude: here.longitude) }

        isSearching = true
        searchWatchdog?.cancel()
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, self.isSearching else { return }
            self.isSearching = false
            self.searchSessions.values.forEach { $0.cancel() }
            self.searchSessions.removeAll()
            // Молчаливый отказ — почти всегда ключ: SDK на него не отвечает
            // вовсе, а уходит в повторы. Поднимаем ту же плашку, что и на
            // явный `YRTForbiddenError`, иначе на экране остаётся пустая
            // сетка, по которой ничего не понять.
            self.keyRejected = true
        }
        searchWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: watchdog)

        var collected: [PlaceKind: [MapPin]] = [:]
        var pending = kinds.count

        for kind in kinds {
            searchSessions[kind]?.cancel()
            searchSessions[kind] = searchManager.submit(
                withText: kind.query,
                geometry: geometry,
                searchOptions: options
            ) { [weak self] response, error in
                guard let self else { return }
                pending -= 1
                if let response {
                    collected[kind] = Self.pins(from: response, kind: kind)
                } else if let error {
                    if Self.isKeyRejected(error) {
                        self.keyRejected = true
                    } else if pending == 0, collected.isEmpty {
                        self.message = "Не удалось загрузить места"
                    }
                }
                guard pending == 0 else { return }
                self.searchWatchdog?.cancel()
                self.isSearching = false
                self.found = kinds.flatMap { collected[$0] ?? [] }
                self.redraw()
            }
        }
    }

    /// То же, но с ожиданием конца поиска — для «потянуть, чтобы обновить».
    ///
    /// `refreshable` держит индикатор ровно до возврата из функции, а SDK
    /// отдаёт результат в замыкание, и связать их можно только ожиданием.
    /// Опрос, а не продолжение: обработчиков у поиска столько же, сколько
    /// активных типов, и какой из них последний — заранее неизвестно. Вечным
    /// ожидание не станет — его обрывает тот же сторож на 15 секунд.
    @MainActor
    func refresh() async {
        search()
        while isSearching {
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
    }

    /// Отказ по ключу приходит вложенной ошибкой SDK — `YRTForbiddenError`
    /// или `YRTUnauthorizedError`. Разбирать текст сообщения нельзя: он
    /// приходит с сервера и меняется без предупреждения.
    private static func isKeyRejected(_ error: Error) -> Bool {
        let underlying = (error as NSError).userInfo[YRTUnderlyingErrorKey as String]
        return underlying is YRTForbiddenError || underlying is YRTUnauthorizedError
    }

    private static func pins(from response: YMKSearchResponse, kind: PlaceKind) -> [MapPin] {
        response.collection.children.compactMap { item -> MapPin? in
            guard let object = item.obj,
                  let point = object.geometry.first?.point else { return nil }
            let title = object.name ?? kind.singular
            return MapPin(id: "\(kind.rawValue)-\(point.latitude)-\(point.longitude)",
                          title: title,
                          subtitle: object.descriptionText,
                          kind: kind,
                          latitude: point.latitude,
                          longitude: point.longitude,
                          source: .found,
                          phone: phone(of: object),
                          contacts: contacts(of: object))
        }
    }

    /// Онлайн-запись, мессенджеры и сайт из карточки организации. Лежат там
    /// же, где телефон, — в метаданных бизнеса.
    private static func contacts(of object: YMKGeoObject) -> [ContactLink] {
        let business = object.metadataContainer
            .getItemOf(YMKSearchBusinessObjectMetadata.self) as? YMKSearchBusinessObjectMetadata
        guard let business else { return [] }
        return BusinessContacts.links(from: business.links.map { (href: $0.link.href, tag: $0.tag) })
    }

    /// Телефон организации из ответа поиска.
    ///
    /// Лежит не в самом объекте, а в его контейнере метаданных: гео-объект у
    /// Яндекса общий для адреса, остановки и организации, и «часы работы,
    /// рубрики, телефоны» есть только у последней. Нет метаданных или нет
    /// номера — честный `nil`, и кнопки «Позвонить» на карточке не будет.
    private static func phone(of object: YMKGeoObject) -> String? {
        let business = object.metadataContainer
            .getItemOf(YMKSearchBusinessObjectMetadata.self) as? YMKSearchBusinessObjectMetadata
        guard let business else { return nil }
        return PhoneFormat.first(of: business.phones.map(\.formattedNumber))
    }

    // MARK: - Ближайший сервис

    /// Найти ближайший к пользователю автосервис и открыть его карточку.
    ///
    /// Сюда ведёт «Записаться» с главной. Ищем вокруг пользователя, а не по
    /// видимой области: карта в этот момент может смотреть куда угодно, а
    /// вопрос — «куда мне ехать отсюда».
    func showNearestService() {
        selected = nil
        // Сервисы должны быть видны на карте, иначе выбранная точка
        // окажется карточкой без значка.
        if !activeKinds.contains(.service) { activeKinds.insert(.service) }

        guard let here else {
            switch location.authorizationStatus {
            case .denied, .restricted:
                message = "Разрешите доступ к геопозиции, чтобы найти ближайший сервис"
            default:
                wantsNearestService = true
                isFindingService = true
                requestLocation()
            }
            return
        }
        findNearestService(from: here)
    }

    private func findNearestService(from here: CLLocationCoordinate2D) {
        wantsNearestService = false
        isFindingService = true

        // Квадрат ±10 км: в городе сервис найдётся в первых сотнях метров,
        // за городом — хотя бы в соседнем посёлке.
        let dLat = 0.09
        let dLon = dLat / max(0.2, cos(here.latitude * .pi / 180))
        let box = YMKBoundingBox(
            southWest: YMKPoint(latitude: here.latitude - dLat, longitude: here.longitude - dLon),
            northEast: YMKPoint(latitude: here.latitude + dLat, longitude: here.longitude + dLon))

        let options = YMKSearchOptions()
        options.searchTypes = .biz
        options.resultPageSize = 32
        options.userPosition = YMKPoint(latitude: here.latitude, longitude: here.longitude)

        nearestSession?.cancel()
        nearestSession = searchManager.submit(
            withText: PlaceKind.service.query,
            geometry: YMKGeometry(boundingBox: box),
            searchOptions: options
        ) { [weak self] response, error in
            guard let self else { return }
            self.isFindingService = false
            if let error, Self.isKeyRejected(error) {
                self.keyRejected = true
                return
            }
            let pins = response.map { Self.pins(from: $0, kind: .service) } ?? []
            let origin = GeoPoint(latitude: here.latitude, longitude: here.longitude)
            guard let index = MapGeo.nearest(to: origin, among: pins.map(\.point)) else {
                self.message = response == nil ? "Не удалось найти сервисы рядом"
                                                : "Рядом не нашлось автосервисов"
                return
            }
            let pin = pins[index]
            if !self.found.contains(where: { $0.id == pin.id }) {
                self.found.append(pin)
                self.redraw()
            }
            self.nearestServiceID = pin.id
            self.selected = pin
            // Камера к сервису, и уже оттуда — обычный поиск по видимой
            // области: вокруг появятся остальные места.
            self.move(to: pin.coordinate, zoom: 15) { [weak self] in self?.search() }
        }
    }

    // MARK: - Отрисовка

    /// Найденное у Яндекса за вычетом того, что уже сохранено.
    ///
    /// Добавленный в избранное бизнес приходит из поиска ещё раз — он же
    /// никуда с карты не делся. Без вычитания он вставал бы второй точкой
    /// поверх себя же и второй строкой в списке, и обе бы жили своей жизнью:
    /// звезда у одной, удаление у другой.
    var nearby: [MapPin] {
        found.filter { pin in
            !saved.contains { place in
                MapGeo.isSamePlace(place.point, title: place.title,
                                   pin.point, title: pin.title)
            }
        }
    }

    private var visiblePins: [MapPin] {
        let mine = saved
            .filter { activeKinds.contains($0.kind) }
            .map { MapPin(place: $0) }
        return mine + nearby
    }

    private func redraw() {
        guard let placemarks else { return }
        placemarks.clear()
        for pin in visiblePins {
            let mark = placemarks.addPlacemark()
            mark.geometry = YMKPoint(latitude: pin.latitude, longitude: pin.longitude)
            mark.setIconWith(Self.icon(for: pin))
            // Тап возвращает нам саму точку: искать её потом по координате
            // значит промахиваться на двух местах в одном доме.
            mark.userData = pin.id as NSString
        }
    }

    /// Значок точки. Свой рисуется, а не берётся из SDK: у него значков нет
    /// вовсе, а SF Symbol нужного цвета получается из шрифта одной строкой.
    private static func icon(for pin: MapPin) -> UIImage {
        let side: CGFloat = 34
        let tint = UIColor(pin.kind.tint)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { context in
            let rect = CGRect(x: 1, y: 1, width: side - 2, height: side - 2)
            // Свои места отличаются от найденных заливкой, а не цветом: цвет
            // здесь уже занят типом.
            let path = UIBezierPath(ovalIn: rect)
            (pin.isSaved ? tint : UIColor.white).setFill()
            path.fill()
            tint.setStroke()
            path.lineWidth = 2
            path.stroke()

            let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            let glyph = UIImage(systemName: pin.kind.symbol, withConfiguration: config)?
                .withTintColor(pin.isSaved ? .white : tint, renderingMode: .alwaysOriginal)
            if let glyph {
                let size = glyph.size
                glyph.draw(in: CGRect(x: (side - size.width) / 2,
                                      y: (side - size.height) / 2,
                                      width: size.width, height: size.height))
            }
            _ = context
        }
    }

    // MARK: - Передача в Яндекс Карты

    /// Маршрут до точки — сразу в приложении Яндекс Карт, а без него — на сайте.
    ///
    /// Своего маршрута в приложении больше нет: считать его, рисовать и
    /// показывать время ради ещё одного тапа до навигатора незачем (решение
    /// пользователя 23.09.2026). Начало маршрута пустое (`rtext=~точка`) —
    /// Яндекс Карты ведут от своей геопозиции, и наша для этого не нужна.
    ///
    /// Схему `yandexmaps` нельзя просто открыть «на удачу»: `canOpenURL` без
    /// объявления схемы в `LSApplicationQueriesSchemes` всегда отвечает «нет».
    /// Объявление лежит в `AppMVP/Resources/Info.plist`.
    func openInYandexMaps(to pin: MapPin) {
        let to = "\(pin.latitude),\(pin.longitude)"
        let app = URL(string: "yandexmaps://maps.yandex.ru/?rtext=~\(to)&rtt=auto")
        let web = URL(string: "https://yandex.ru/maps/?rtext=~\(to)&rtt=auto")

        if let app, UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
        } else if let web {
            UIApplication.shared.open(web)
        }
    }

    // MARK: - Своя позиция

    /// Показать точку на карте: выбрать её и подвести камеру.
    ///
    /// Отсюда уходит переход «строка списка → карта»: список знает, что
    /// выбрали, но не знает, где стоит камера, и двигать её должен тот, кто
    /// владеет картой.
    func show(_ pin: MapPin) {
        selected = pin
        move(to: pin.coordinate, zoom: 16)
    }

    func centerOnMe() {
        guard let here else {
            message = "Не видно вашего местоположения"
            requestLocation()
            return
        }
        move(to: here, zoom: 15)
    }

    private func move(to coordinate: CLLocationCoordinate2D, zoom: Float,
                      then finished: (() -> Void)? = nil) {
        map?.move(
            with: YMKCameraPosition(
                target: YMKPoint(latitude: coordinate.latitude, longitude: coordinate.longitude),
                zoom: zoom, azimuth: 0, tilt: 0),
            animation: YMKAnimation(type: .smooth, duration: 0.4),
            cameraCallback: { _ in finished?() })
    }
}

// MARK: - Тап по точке

extension MapController: YMKMapObjectTapListener {
    func onMapObjectTap(with mapObject: YMKMapObject, point: YMKPoint) -> Bool {
        guard let id = mapObject.userData as? String,
              let pin = visiblePins.first(where: { $0.id == id }) else { return false }
        selected = pin
        return true
    }
}

// MARK: - Тап по карте

extension MapController: YMKMapInputListener {
    func onMapTap(with map: YMKMap, point: YMKPoint) {
        // Тап по пустому месту закрывает карточку — так же ведут себя
        // системные карты.
        selected = nil
    }

    /// Долгое нажатие ставит новое место. Жест выбран не случайно: обычный тап
    /// уже занят выбором точки, а отдельная кнопка «поставить точку» потребовала
    /// бы режима, из которого надо выходить.
    func onMapLongTap(with map: YMKMap, point: YMKPoint) {
        selected = nil
        draft = PlaceDraft(latitude: point.latitude, longitude: point.longitude)
    }
}

// MARK: - Геопозиция

extension MapController: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        here = last.coordinate
        hasLocation = true

        if wantsNearestService {
            // Камеру подведёт сам поиск — к найденному сервису, а не к нам.
            didCenter = true
            findNearestService(from: last.coordinate)
            return
        }

        guard !didCenter else { return }
        didCenter = true
        // Поиск — строго **после** того, как камера доехала. Он берёт видимую
        // область, а в момент первой геопозиции она ещё всемирная: запрос
        // уходил по всему глобусу и возвращался пустым. На живой карте это и
        // выглядело как «точек нет», без единой ошибки в логе.
        move(to: last.coordinate, zoom: 14) { [weak self] in self?.search() }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        hasLocation = false
    }
}

/// Обёртка карты. Вся работа с SDK живёт в контроллере, поэтому здесь только
/// создание вьюхи и передача её контроллеру.
struct YandexMapView: UIViewRepresentable {
    let controller: MapController

    /// Контейнер, а не сама карта: инициализатор `YMKMapView` может вернуть
    /// nil (например, без доступного GPU), а тип вьюхи у представимого обязан
    /// быть неопциональным. Падать из-за этого нельзя.
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        guard let map = YMKMapView(frame: .zero) else { return container }

        map.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(map)
        NSLayoutConstraint.activate([
            map.topAnchor.constraint(equalTo: container.topAnchor),
            map.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            map.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            map.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        controller.attach(to: map)
        return container
    }

    /// Пусто намеренно: карта не перерисовывается от состояния SwiftUI,
    /// контроллер меняет её сам. Иначе каждый кадр интерфейса дёргал бы SDK.
    func updateUIView(_ uiView: UIView, context: Context) {}
}
