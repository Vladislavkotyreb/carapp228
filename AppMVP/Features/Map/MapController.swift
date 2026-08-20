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

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isSaved: Bool {
        if case .saved = source { return true }
        return false
    }
}

/// Построенный маршрут в том виде, в каком его показывает карточка.
struct RouteSummary: Equatable {
    let distance: String
    let time: String
    let destination: MapPin
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
        didSet { if activeKinds != oldValue { redraw(); search() } }
    }
    @Published private(set) var found: [MapPin] = []
    @Published var selected: MapPin?
    @Published private(set) var route: RouteSummary?
    @Published private(set) var isSearching = false
    @Published private(set) var isRouting = false
    @Published var draft: PlaceDraft?
    @Published var message: String?
    /// Есть ли разрешение и позиция. Без неё маршрут строить не от чего.
    @Published private(set) var hasLocation = false
    /// Яндекс отверг ключ. Отдельным состоянием, а не текстом ошибки: без
    /// ключа карта показывает пустую сетку и выглядит сломанной, хотя сломан
    /// не код. Определяется по типу ошибки из SDK, а не по её тексту.
    @Published private(set) var keyRejected = false

    /// Сохранённые места. Их держит `@Query` на экране и передаёт сюда:
    /// контроллеру не нужен доступ к базе, ему нужен только список.
    private(set) var saved: [Place] = []

    // MARK: Владение объектами SDK

    private weak var map: YMKMap?
    private var placemarks: YMKMapObjectCollection?
    private var routeLine: YMKMapObjectCollection?
    private var userLayer: YMKUserLocationLayer?

    /// Сессии держим сильно: в SDK они отменяются, как только на них не
    /// осталось ссылки, и запрос молча не доходит.
    private var searchSessions: [PlaceKind: YMKSearchSession] = [:]
    /// Сторож на зависший поиск. При отказе по ключу или на мёртвой сети SDK
    /// уходит в бесконечные повторы и обработчик не вызывает вовсе — без
    /// сторожа индикатор крутился бы всегда.
    private var searchWatchdog: DispatchWorkItem?
    private var routeSession: YMKDrivingSession?
    private lazy var searchManager =
        YMKSearchFactory.instance().createSearchManager(with: .combined)
    private lazy var router =
        YMKDirectionsFactory.instance().createDrivingRouter(withType: .combined)

    private let location = CLLocationManager()
    private var here: CLLocationCoordinate2D?
    /// Камера прыгает к пользователю только один раз за открытие экрана:
    /// иначе каждое уточнение позиции утаскивало бы карту у него из-под пальца.
    private var didCenter = false

    // MARK: - Жизненный цикл

    /// Вызывается обёрткой, когда карта создана.
    func attach(to mapView: YMKMapView) {
        let map = mapView.mapWindow.map
        self.map = map

        placemarks = map.mapObjects.add()
        routeLine = map.mapObjects.add()

        // Слушатели SDK хранит слабо — живыми их держит сам контроллер,
        // который лежит в `@StateObject` экрана.
        placemarks?.addTapListener(with: self)
        map.addInputListener(with: self)

        let layer = YMKMapKit.sharedInstance()
            .createUserLocationLayer(with: mapView.mapWindow)
        layer.setVisibleWithOn(true)
        userLayer = layer

        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyHundredMeters
        requestLocation()

        redraw()
    }

    func detach() {
        searchWatchdog?.cancel()
        searchSessions.values.forEach { $0.cancel() }
        searchSessions.removeAll()
        routeSession?.cancel()
        routeSession = nil
        location.stopUpdatingLocation()
        map = nil
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
        guard let map, !activeKinds.isEmpty else {
            if activeKinds.isEmpty { found = []; redraw() }
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
        let kinds = activeKinds
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
                          source: .found)
        }
    }

    // MARK: - Отрисовка

    private var visiblePins: [MapPin] {
        let mine = saved
            .filter { activeKinds.contains($0.kind) }
            .map { place in
                MapPin(id: "saved-\(place.persistentModelID.hashValue)",
                       title: place.title,
                       subtitle: place.note,
                       kind: place.kind,
                       latitude: place.latitude,
                       longitude: place.longitude,
                       source: .saved(place.persistentModelID))
            }
        return mine + found
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

    // MARK: - Маршрут

    /// Строит маршрут от текущей позиции до точки и показывает его на карте.
    ///
    /// Считаем сами, хотя дальше маршрут всё равно уходит в Яндекс Карты: без
    /// этого кнопка «Открыть в Яндекс Картах» была бы предложением уйти в
    /// никуда, не сказав ни времени, ни расстояния.
    func buildRoute(to pin: MapPin) {
        guard let here else {
            message = "Не видно вашего местоположения"
            requestLocation()
            return
        }

        isRouting = true
        route = nil
        let points = [
            YMKRequestPoint(point: YMKPoint(latitude: here.latitude, longitude: here.longitude),
                            type: .waypoint, pointContext: nil,
                            drivingArrivalPointId: nil, indoorLevelId: nil),
            YMKRequestPoint(point: YMKPoint(latitude: pin.latitude, longitude: pin.longitude),
                            type: .waypoint, pointContext: nil,
                            drivingArrivalPointId: nil, indoorLevelId: nil)
        ]

        routeSession?.cancel()
        routeSession = router.requestRoutes(
            with: points,
            drivingOptions: YMKDrivingOptions(),
            vehicleOptions: YMKDrivingVehicleOptions()
        ) { [weak self] routes, _ in
            guard let self else { return }
            self.isRouting = false
            guard let first = routes?.first else {
                self.message = "Не удалось построить маршрут"
                return
            }
            self.draw(route: first)
            let weight = first.metadata.weight
            self.route = RouteSummary(distance: weight.distance.text,
                                      time: weight.timeWithTraffic.text,
                                      destination: pin)
        }
    }

    private func draw(route: YMKDrivingRoute) {
        guard let routeLine else { return }
        routeLine.clear()
        let line = routeLine.addPolyline(with: route.geometry)
        // Через `style`, а не через отдельные свойства линии: те помечены
        // устаревшими и в следующей версии SDK исчезнут.
        let style = YMKLineStyle()
        style.strokeWidth = 5
        style.outlineWidth = 1
        style.outlineColor = UIColor.white.withAlphaComponent(0.6)
        line.style = style
        line.setStrokeColorWith(UIColor(Figma.accentsBlue))

        // Показываем маршрут целиком, а не только его начало.
        if let map {
            let position = map.cameraPosition(with: YMKGeometry(polyline: route.geometry))
            let padded = YMKCameraPosition(target: position.target,
                                           zoom: max(position.zoom - 0.4, 2),
                                           azimuth: position.azimuth,
                                           tilt: position.tilt)
            map.move(with: padded,
                     animation: YMKAnimation(type: .smooth, duration: 0.45),
                     cameraCallback: nil)
        }
    }

    func clearRoute() {
        routeSession?.cancel()
        routeSession = nil
        routeLine?.clear()
        route = nil
        isRouting = false
    }

    // MARK: - Передача в Яндекс Карты

    /// Отдаёт маршрут приложению Яндекс Карт, а если его нет — сайту.
    ///
    /// Схему `yandexmaps` нельзя просто открыть «на удачу»: `canOpenURL` без
    /// объявления схемы в `LSApplicationQueriesSchemes` всегда отвечает «нет».
    /// Объявление лежит в `AppMVP/Resources/Info.plist`.
    func openInYandexMaps() {
        guard let here, let destination = route?.destination ?? selected else { return }
        let from = "\(here.latitude),\(here.longitude)"
        let to = "\(destination.latitude),\(destination.longitude)"

        let app = URL(string: "yandexmaps://maps.yandex.ru/?rtext=\(from)~\(to)&rtt=auto")
        let web = URL(string: "https://yandex.ru/maps/?rtext=\(from)~\(to)&rtt=auto")

        if let app, UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
        } else if let web {
            UIApplication.shared.open(web)
        }
    }

    // MARK: - Своя позиция

    func centerOnMe() {
        guard let here else {
            message = "Не видно вашего местоположения"
            requestLocation()
            return
        }
        move(to: here, zoom: 15)
    }

    private func move(to coordinate: CLLocationCoordinate2D, zoom: Float) {
        map?.move(
            with: YMKCameraPosition(
                target: YMKPoint(latitude: coordinate.latitude, longitude: coordinate.longitude),
                zoom: zoom, azimuth: 0, tilt: 0),
            animation: YMKAnimation(type: .smooth, duration: 0.4),
            cameraCallback: nil)
    }
}

// MARK: - Тап по точке

extension MapController: YMKMapObjectTapListener {
    func onMapObjectTap(with mapObject: YMKMapObject, point: YMKPoint) -> Bool {
        guard let id = mapObject.userData as? String,
              let pin = visiblePins.first(where: { $0.id == id }) else { return false }
        clearRoute()
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
        clearRoute()
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

        guard !didCenter else { return }
        didCenter = true
        move(to: last.coordinate, zoom: 14)
        // Первый поиск — только когда есть где искать: до появления позиции
        // карта стоит над нулевым меридианом, и находить там нечего.
        search()
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
