import SwiftData
import SwiftUI
import YandexMapsMobile

/// Поездка для экрана: значения, снятые с `Trip`. Маршрут раскодируется один
/// раз здесь, а не на каждой перерисовке карточки или шторки.
struct TripDetails: Identifiable, Equatable {
    let id: String
    /// «8 октября 2026, 21:16» — подпись карточки в истории.
    let cardTitle: String
    /// «Поездка 8 октября» — заголовок экрана поездки.
    let sheetTitle: String
    let car: String?
    /// Госномер в виде «В 777 ОР 777»; пустой у машины без номера.
    let plate: String
    /// Фото машины: своё или, если его нет, кадр каталога по этому имени.
    let photo: Data?
    let catalogSlug: String?
    /// «8 октября 2026, 21:14» и то же для конца — строки хода поездки.
    let start: String
    let end: String
    /// Адреса начала и конца; `nil`, пока геокодер не ответил.
    let startAddress: String?
    let endAddress: String?
    let distance: String
    let duration: String
    let speed: String?
    let route: [GeoPoint]
    /// Имя кадра карты в кэше — см. `Trip.snapshotKey`.
    let snapshotKey: String
    /// Сколько километров уйдёт из пробега, если поездку удалить.
    let kmBack: Int
    /// Расстояние для поля правки: «3,9».
    let kmField: String

    init(_ trip: Trip, calendar: Calendar = .current) {
        id = "\(trip.persistentModelID.hashValue)"
        cardTitle = TripTrack.cardTitle(trip.startedAt, calendar: calendar)
        sheetTitle = TripTrack.sheetTitle(trip.startedAt, calendar: calendar)
        car = trip.car?.name
        plate = trip.car.map { $0.plate.isEmpty ? "" : PlateFormat.format($0.plate) } ?? ""
        photo = trip.car?.photo
        catalogSlug = trip.car.flatMap {
            CarCatalog.slug(name: $0.name, generation: $0.generation, plate: $0.plate)
        }
        start = TripTrack.cardTitle(trip.startedAt, calendar: calendar)
        end = TripTrack.cardTitle(trip.endedAt, calendar: calendar)
        startAddress = trip.startAddress
        endAddress = trip.endAddress
        distance = MapGeo.distanceLabel(meters: trip.meters)
        let seconds = trip.endedAt.timeIntervalSince(trip.startedAt)
        duration = TripTrack.durationLabel(seconds: seconds)
        speed = TripTrack.speedLabel(meters: trip.meters, seconds: seconds)
        route = trip.track.map(TripTrack.decode) ?? []
        snapshotKey = trip.snapshotKey
        kmBack = TripEdits.kmBack(for: trip)
        kmField = TripMath.kmField(trip.meters)
    }

    var hasMap: Bool { route.count > 1 && MapKitKey.isConfigured }
}

/// Правки поездки с экранов — удаление и новое расстояние. Пробег машины
/// идёт следом: поездка его меняла, значит, и правка её меняет его.
@MainActor
enum TripEdits {
    /// Километры, которые поездка добавила пробегу и которые удаление снимет.
    /// Ниже пробега последнего ТО одометр не опускается: запись о ТО —
    /// показание приборки, оно вернее счёта поездок.
    nonisolated static func kmBack(for trip: Trip) -> Int {
        guard let car = trip.car else { return 0 }
        let back = TripMath.forget(meters: trip.meters, trackedKm: car.trackedKm ?? 0,
                                   carry: car.tripCarry ?? 0)
        return min(back.km, max(0, car.odometer - floor(of: car)))
    }

    /// Удалить поездку: её километры уходят из пробега, кадр карты — из
    /// кэша, а зона автоопределения на её конце снимается — раз поездка
    /// лишняя, машина там не вставала.
    static func remove(_ trip: Trip, in context: ModelContext) {
        guard trip.modelContext != nil else { return }
        let end = trip.track.map(TripTrack.decode)?.last
        if let car = trip.car {
            let back = TripMath.forget(meters: trip.meters, trackedKm: car.trackedKm ?? 0,
                                       carry: car.tripCarry ?? 0)
            car.odometer -= kmBack(for: trip)
            // Счёт поездок пустой после сверки с приборкой — таким и остаётся.
            if car.trackedKm != nil { car.trackedKm = back.trackedKm }
            if car.tripCarry != nil { car.tripCarry = back.carry }
        }
        TripSnapshots.remove(for: trip.snapshotKey)
        context.delete(trip)
        try? context.save()
        if let end { TripTracker.shared.forgetSpot(at: end) }
    }

    /// Новое расстояние поездки. Линия маршрута остаётся как записана:
    /// человек правит число, а не путь.
    static func resize(_ trip: Trip, to meters: Double, in context: ModelContext) {
        guard trip.modelContext != nil, meters != trip.meters else { return }
        if let car = trip.car {
            let shift = TripMath.adjust(from: trip.meters, to: meters,
                                        trackedKm: car.trackedKm ?? 0, carry: car.tripCarry ?? 0)
            car.odometer = max(floor(of: car), car.odometer + shift.km)
            car.trackedKm = shift.trackedKm
            car.tripCarry = shift.carry
        }
        trip.meters = meters
        try? context.save()
    }

    private nonisolated static func floor(of car: Car) -> Int {
        car.services.map(\.mileage).max() ?? 0
    }
}

/// Карточка с действиями по свайпу влево — «Изменить» и «Удалить», как в
/// системных списках. `swipeActions` работает только в `List`, а история —
/// стопка в прокрутке, поэтому строка — горизонтальная прокрутка из карточки
/// и кнопок за ней: жест разбирает сама система, и вертикальной прокрутке
/// страницы он не мешает (`TRAPS.md` — про свои жесты поверх скролла).
struct SwipeRow<Content: View>: View {
    let onEdit: () -> Void
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    /// Что у левого края: карточка или кнопки. Нажали кнопку — строка
    /// закрывается обратно.
    @State private var shown: Int? = SwipeRowLayout.card

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SwipeRowLayout.gap) {
                content
                    .containerRelativeFrame(.horizontal)
                    .id(SwipeRowLayout.card)
                HStack(spacing: SwipeRowLayout.gap) {
                    action("pencil", "Изменить", tint: Figma.labelsPrimary, perform: onEdit)
                    action("trash", "Удалить", tint: Figma.accentsRed, perform: onDelete)
                }
                .id(SwipeRowLayout.actions)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $shown)
        // Кнопки спрятаны за краем — читалке экрана они нужны действиями.
        .accessibilityAction(named: "Изменить", onEdit)
        .accessibilityAction(named: "Удалить", onDelete)
    }

    private func action(_ symbol: String, _ title: String, tint: Color,
                        perform: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { shown = SwipeRowLayout.card }
            perform()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(tint)
            .frame(width: SwipeRowLayout.action)
            .frame(maxHeight: .infinity)
            .background(Figma.fillsTertiary,
                        in: RoundedRectangle(cornerRadius: SwipeRowLayout.radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: SwipeRowLayout.radius, style: .continuous))
        }
        .buttonStyle(CardPressStyle())
    }
}

/// Размеры строки со свайпом. Вне `SwipeRow`: у обобщённого типа не бывает
/// хранимых статических свойств.
private enum SwipeRowLayout {
    static let card = 0
    static let actions = 1
    static let action: CGFloat = 84
    static let gap: CGFloat = 8
    static let radius: CGFloat = 26
}

/// Карточка поездки в истории — как в истории Делимобиля (образец
/// пользователя, 08.10.2026): сверху карта с путём, под ней дата со временем
/// и машина, справа вместо цены — расстояние. У поездки без маршрута карты
/// нет, карточка короче.
struct TripCard: View {
    let trip: TripDetails
    /// В списке одной машины её имя в каждой карточке — шум: вместо него
    /// стоит время в пути.
    let showsCar: Bool

    /// Кадр карты. Живая карта в каждой карточке стоила 33 МБ: шесть карточек
    /// — 217 МБ вместо 52 (замер 08.10.2026). Поэтому карточка показывает
    /// картинку: её один раз рисует `TripSnapshotter` без единой вьюхи карты
    /// и кладёт в кэш; при следующем запуске карта не создаётся вовсе.
    @State private var snapshot: UIImage?

    init(trip: TripDetails, showsCar: Bool = true) {
        self.trip = trip
        self.showsCar = showsCar
        _snapshot = State(initialValue: TripSnapshots.image(for: trip.snapshotKey))
    }

    private enum Layout {
        static let map: CGFloat = 150
        /// Подпись под картой: 16 + две строки + 16. Высота задана, а не
        /// выходит из текста: главная считает высоту ленты заранее
        /// (`CarMainView.historyHeight`), и карточка обязана с ней сойтись.
        static let caption: CGFloat = 72
        static let radius: CGFloat = 26
    }

    /// Высота карточки: с картой и без.
    static func height(hasMap: Bool) -> CGFloat {
        (hasMap ? Layout.map : 0) + Layout.caption
    }

    var body: some View {
        VStack(spacing: 0) {
            if trip.hasMap {
                // Ширину кадра задаёт сама карточка: кадр шире неё обрезал бы
                // логотип Яндекс Карт в углу, а он должен быть виден целиком.
                GeometryReader { geo in
                    // Пока кадра нет — тёмная подложка в цвет ночной карты.
                    Rectangle()
                        .fill(Figma.sheetBackground)
                        .overlay {
                            if let snapshot {
                                Image(uiImage: snapshot)
                                    .resizable()
                                    .scaledToFill()
                                    .transition(.opacity)
                            }
                        }
                        .clipped()
                        .task(id: geo.size.width) {
                            guard snapshot == nil, geo.size.width > 0 else { return }
                            let image = await TripSnapshotter.shared.image(
                                key: trip.snapshotKey, route: trip.route,
                                size: CGSize(width: geo.size.width, height: Layout.map))
                            withAnimation(.easeOut(duration: 0.2)) { snapshot = image }
                        }
                }
                .frame(height: Layout.map)
                .accessibilityHidden(true)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.cardTitle)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Figma.labelsPrimary)
                    if let note = showsCar ? trip.car : trip.duration {
                        Text(note)
                            .font(.system(size: 15))
                            .foregroundStyle(Figma.graysGray)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(trip.distance)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Figma.labelsPrimary)
            }
            .padding(.horizontal, 16)
            .frame(height: Layout.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Figma.fillsTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Layout.radius, style: .continuous))
    }
}

/// Экран поездки — по образцу Делимобиля: заголовок «Поездка 8 октября»,
/// слева марка и номер, справа картинка машины, ниже карта с путём, ход
/// поездки (время и адрес начала и конца) и цифры. Адреса приходят от
/// геокодера Яндекса (`TripGeocoder`); пока их нет, стоит «Начало» и «Конец».
///
/// Фон чёрный, а не серый фон шторок: кадры каталога сняты на чёрном, и на
/// сером картинка машины встала бы прямоугольной плашкой.
///
/// Внизу — «Удалить поездку»: автоопределение не отличает свою машину от
/// такси, уехавшего от того же места, и лишнюю поездку убирает человек.
struct TripSheet: View {
    let trip: TripDetails
    let onDelete: () -> Void
    let onClose: () -> Void

    @State private var carImage: UIImage?
    @State private var confirming = false

    private enum Layout {
        static let margin: CGFloat = 16
        static let section: CGFloat = 24
        static let map: CGFloat = 240
        static let radius: CGFloat = 26
        static let row: CGFloat = 52
        /// Картинка машины справа от марки.
        static let carWidth: CGFloat = 170
        static let carHeight: CGFloat = 96
        /// Ход поездки: точка, линия между точками, колонка под них.
        static let dot: CGFloat = 12
        static let rail: CGFloat = 24
        /// Высота затухания под панелью с крестиком поверх её собственной зоны.
        static let barFade: CGFloat = 16
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Layout.section) {
                    Text(trip.sheetTitle)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Figma.labelsPrimary)

                    carHeader
                    map
                    timeline
                    stats
                    deleteButton
                }
                .padding(.horizontal, Layout.margin)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Figma.backgroundsPrimary)
            // С кнопкой удаления экран стал прокручиваться, и заголовок уезжал
            // под крестик (кадр 08.10.2026). Под панелью контент гаснет в фон —
            // тот же приём, что под статус-баром на «Ещё».
            .overlay(alignment: .top) {
                LinearGradient(colors: [Figma.backgroundsPrimary, Figma.backgroundsPrimary.opacity(0)],
                               startPoint: .init(x: 0.5, y: 0.7), endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
                    .frame(height: Layout.barFade)
                    .allowsHitTesting(false)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if #available(iOS 26.0, *) {
                        Button(role: .close, action: onClose)
                    } else {
                        Button(action: onClose) { Image(systemName: "xmark") }
                            .accessibilityLabel("Закрыть")
                    }
                }
            }
        }
        // Кнопка панели без подкраски: акцент приложения белый.
        .tint(Figma.labelsPrimary)
        .presentationBackground(Figma.backgroundsPrimary)
        .presentationDragIndicator(.visible)
        .task(id: trip.id) {
            // Своё фото важнее каталожного — тот же порядок, что на главной.
            if let photo = trip.photo {
                carImage = await ImageLoader.decode([photo]).first
            } else if let slug = trip.catalogSlug,
                      let url = Bundle.main.url(forResource: slug, withExtension: "heic",
                                                subdirectory: "CarCatalog") {
                carImage = UIImage(contentsOfFile: url.path)
            }
        }
    }

    // MARK: - Машина

    @ViewBuilder
    private var carHeader: some View {
        if let name = trip.car {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Figma.labelsPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !trip.plate.isEmpty {
                        Text(trip.plate)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Figma.labelsPrimary)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Spacer(minLength: 0)
                if let carImage {
                    Image(uiImage: carImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Layout.carWidth, height: Layout.carHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Карта

    @ViewBuilder
    private var map: some View {
        if trip.hasMap {
            TripMapView(route: trip.route)
                .frame(height: Layout.map)
                .clipShape(RoundedRectangle(cornerRadius: Layout.radius, style: .continuous))
                .accessibilityLabel("Карта с\u{00A0}маршрутом поездки")
        } else {
            VStack(spacing: 8) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 32, weight: .light))
                Text("Маршрут не\u{00A0}записан")
                    .font(.system(size: 15))
            }
            .foregroundStyle(Figma.graysGray)
            .frame(maxWidth: .infinity)
            .frame(height: Layout.map / 2)
            .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: Layout.radius))
        }
    }

    // MARK: - Ход поездки

    /// Начало и конец друг под другом, слева — точки, соединённые линией.
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 20) {
            stop(time: trip.start, title: trip.startAddress ?? "Начало")
            stop(time: trip.end, title: trip.endAddress ?? "Конец")
        }
        .padding(.leading, Layout.rail + 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { rail }
    }

    private func stop(time: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(time)
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Figma.graysGray)
            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(Figma.labelsPrimary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    /// Кольцо начала, линия, сплошная зелёная точка конца — те же цвета, что
    /// у точек на карте.
    private var rail: some View {
        VStack(spacing: 4) {
            Circle()
                .strokeBorder(Figma.labelsPrimary, lineWidth: 2.5)
                .frame(width: Layout.dot, height: Layout.dot)
            Rectangle()
                .fill(Figma.separatorsOnDark)
                .frame(width: 2)
            Circle()
                .fill(Figma.accentsGreen)
                .frame(width: Layout.dot, height: Layout.dot)
        }
        .frame(width: Layout.rail)
        .padding(.vertical, 12)
        .accessibilityHidden(true)
    }

    // MARK: - Цифры

    private var stats: some View {
        VStack(spacing: 0) {
            statRow("Расстояние", value: trip.distance)
            separator
            statRow("В\u{00A0}пути", value: trip.duration)
            if let speed = trip.speed {
                separator
                statRow("Средняя скорость", value: speed)
            }
        }
        .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: Layout.radius))
    }

    // MARK: - Удаление

    private var deleteButton: some View {
        Button(role: .destructive) {
            confirming = true
        } label: {
            Text("Удалить поездку")
                .font(.system(size: 17))
                .foregroundStyle(Figma.accentsRed)
                .frame(maxWidth: .infinity, minHeight: Layout.row)
                .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: Layout.radius))
                .contentShape(RoundedRectangle(cornerRadius: Layout.radius))
        }
        .buttonStyle(CardPressStyle())
        .confirmationDialog("Удалить поездку?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Удалить", role: .destructive, action: onDelete)
        } message: {
            if trip.kmBack > 0 {
                Text("Пробег уменьшится на\u{00A0}\(NumberFormat.grouped(trip.kmBack))\u{00A0}км")
            }
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 17))
                .foregroundStyle(Figma.labelsPrimary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 17))
                .foregroundStyle(Figma.labelsSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: Layout.row)
        .accessibilityElement(children: .combine)
    }

    private var separator: some View {
        Rectangle()
            .fill(Figma.separatorsOnDark)
            .frame(height: 0.5)
            .padding(.leading, 16)
    }
}

/// Карта с линией маршрута. Неподвижная: стоит внутри прокрутки, и свои
/// жесты карты спорили бы с ней за палец.
struct TripMapView: UIViewRepresentable {
    let route: [GeoPoint]

    func makeUIView(context: Context) -> TripMapContainer {
        let container = TripMapContainer()
        // Инициализатор может вернуть nil без доступного GPU — тогда остаётся
        // пустая подложка, а не падение (как в `YandexMapView`).
        guard let mapView = YMKMapView(frame: .zero) else { return container }
        mapView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: container.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        let map = mapView.mapWindow.map
        map.isScrollGesturesEnabled = false
        map.isZoomGesturesEnabled = false
        map.isTiltGesturesEnabled = false
        map.isRotateGesturesEnabled = false

        Self.draw(route, on: map)

        container.mapView = mapView
        container.route = route
        return container
    }

    func updateUIView(_ uiView: TripMapContainer, context: Context) {}

    /// Ночная карта с линией маршрута и точками начала и конца — одна и та же
    /// на экране поездки и на кадре для карточки.
    static func draw(_ route: [GeoPoint], on map: YMKMap) {
        map.isNightModeEnabled = true
        let points = route.map { YMKPoint(latitude: $0.latitude, longitude: $0.longitude) }
        let line = map.mapObjects.addPolyline(with: YMKPolyline(points: points))
        line.setStrokeColorWith(UIColor(Figma.accentsGreen))
        line.style.strokeWidth = 5
        line.style.outlineWidth = 1.5
        line.style.outlineColor = UIColor.black.withAlphaComponent(0.55)

        if let first = points.first, let last = points.last {
            addDot(at: first, color: .white, to: map)
            addDot(at: last, color: UIColor(Figma.accentsGreen), to: map)
        }
    }

    /// Камера, в которую маршрут входит с полями: полшага масштаба дают поля
    /// примерно в пятую часть кадра. `nil`, если наводить не на что.
    static func camera(for route: [GeoPoint], on map: YMKMap) -> YMKCameraPosition? {
        guard let box = TripTrack.bounds(route) else { return nil }
        let geometry = YMKGeometry(boundingBox: YMKBoundingBox(
            southWest: YMKPoint(latitude: box.southWest.latitude, longitude: box.southWest.longitude),
            northEast: YMKPoint(latitude: box.northEast.latitude, longitude: box.northEast.longitude)))
        let fit = map.cameraPosition(with: geometry)
        return YMKCameraPosition(target: fit.target, zoom: fit.zoom - 0.5, azimuth: 0, tilt: 0)
    }

    /// Точка начала или конца: цветной кружок с тёмной кромкой.
    private static func addDot(at point: YMKPoint, color: UIColor, to map: YMKMap) {
        let side: CGFloat = 18
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let rect = CGRect(x: 2, y: 2, width: side - 4, height: side - 4)
            UIColor.black.withAlphaComponent(0.7).setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: -2, dy: -2)).fill()
            color.setFill()
            UIBezierPath(ovalIn: rect).fill()
        }
        let mark = map.mapObjects.addPlacemark()
        mark.geometry = point
        mark.setIconWith(image)
    }
}

/// Контейнер карты: камеру можно навести на маршрут только когда у окна
/// карты появился размер — в `makeUIView` он ещё нулевой.
final class TripMapContainer: UIView {
    var mapView: YMKMapView?
    var route: [GeoPoint] = []
    private var fitted = CGSize.zero
    private var attempts = 0

    /// Сколько раз ждать размер окна карты, прежде чем сдаться.
    private static let maxAttempts = 20

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let mapView, bounds.width > 0, bounds.height > 0, fitted != bounds.size else { return }
        mapView.layoutIfNeeded()
        let window = mapView.mapWindow
        // Окно карты узнаёт размер позже самой вьюхи. Считать камеру по
        // нулевому окну нельзя: SDK падает на проверке (сбой 08.10.2026,
        // `cameraPositionWithGeometry:focusRect:`), поэтому ждём кадр.
        guard let window, window.width() > 0, window.height() > 0 else {
            attempts += 1
            if attempts < Self.maxAttempts {
                DispatchQueue.main.async { [weak self] in self?.setNeedsLayout() }
            }
            return
        }
        fitted = bounds.size
        if let camera = TripMapView.camera(for: route, on: window.map) {
            window.map.move(with: camera)
        }
    }
}

/// Рисует кадры карт для карточек истории — по одному, без вьюх: у SDK для
/// этого есть окно карты без экрана (`YMKOffscreenMapWindow`). Окно живёт,
/// пока есть очередь, и отпускается вместе с памятью карты.
@MainActor
final class TripSnapshotter: NSObject, YMKMapLoadedListener {
    static let shared = TripSnapshotter()

    /// Сколько ждать тайлы, прежде чем снять кадр как есть.
    private static let timeoutSeconds: TimeInterval = 8

    private struct Job {
        let key: String
        let route: [GeoPoint]
        let size: CGSize
        var waiters: [CheckedContinuation<UIImage?, Never>]
    }

    private var queue: [Job] = []
    private var window: YMKOffscreenMapWindow?
    private var timeout: DispatchWorkItem?

    /// Кадр маршрута: из кэша или нарисованный. `nil` — карты нет вовсе
    /// (нет ключа MapKit или маршрут пуст).
    func image(key: String, route: [GeoPoint], size: CGSize) async -> UIImage? {
        if let cached = TripSnapshots.image(for: key) { return cached }
        guard MapKitKey.isConfigured, route.count > 1 else { return nil }
        #if DEBUG
        // Проверка рисунка без карты: `SIMCTL_CHILD_BEEPY_MAP_OFFLINE=1`.
        if ProcessInfo.processInfo.environment["BEEPY_MAP_OFFLINE"] == "1" {
            return Self.sketch(route, size: size)
        }
        #endif
        return await withCheckedContinuation { continuation in
            // Та же поездка уже в очереди — ждём её кадр, второй не рисуем.
            if let index = queue.firstIndex(where: { $0.key == key }) {
                queue[index].waiters.append(continuation)
            } else {
                queue.append(Job(key: key, route: route, size: size, waiters: [continuation]))
                if queue.count == 1 { start() }
            }
        }
    }

    private func start() {
        guard let job = queue.first else {
            window = nil
            return
        }
        let scale = max(2, UITraitCollection.current.displayScale)
        let window = YMKMapKit.sharedInstance().createOffscreenMapWindow(
            withWidth: Int(job.size.width * scale), height: Int(job.size.height * scale),
            customScaleFactor: Float(scale))
        self.window = window
        let map = window.mapWindow.map
        TripMapView.draw(job.route, on: map)
        if let camera = TripMapView.camera(for: job.route, on: map) { map.move(with: camera) }
        // Слушатель — после наведения камеры: SDK зовёт его один раз.
        map.setMapLoadedListenerWith(self)
        let work = DispatchWorkItem { [weak self] in self?.finish(complete: false) }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeoutSeconds, execute: work)
    }

    nonisolated func onMapLoaded(with statistics: YMKMapLoadStatistics) {
        // SDK зовёт слушателей на главном потоке.
        MainActor.assumeIsolated { finish(complete: true) }
    }

    private func finish(complete: Bool) {
        timeout?.cancel()
        timeout = nil
        guard !queue.isEmpty, let window else { return }
        let job = queue.removeFirst()
        var image = window.captureScreenshot()
        // Без сети карта не догружается, и кадр по таймауту выходит пустым и
        // белым (кадр пользователя 09.10.2026). Тогда вместо него — путь без
        // подложки. На диск такой кадр не кладём: в следующий запуск карта
        // попробует ещё раз.
        if !complete, Self.isBlank(image) {
            image = Self.sketch(job.route, size: job.size)
        }
        TripSnapshots.store(image, for: job.key, onDisk: complete)
        job.waiters.forEach { $0.resume(returning: image) }
        // Окно — на один кадр: следующей поездке новое, очередь пуста — память
        // карты уходит.
        self.window = nil
        start()
    }
}

extension TripSnapshotter {
    private enum Sketch {
        static let inset: CGFloat = 28
        static let line: CGFloat = 5
        static let outline: CGFloat = 8
        static let dot: CGFloat = 14
        /// Сторона уменьшенной копии, по которой меряется яркость кадра.
        static let probe = 8
        /// Ночная карта тёмная; ярче этого — карта не нарисовалась.
        static let blank: CGFloat = 0.8
    }

    /// Кадр без карты: путь зелёной линией на тёмном фоне, начало — белая
    /// точка, конец — зелёная, как на карте.
    static func sketch(_ route: [GeoPoint], size: CGSize) -> UIImage {
        let spots = TripTrack.project(route, width: size.width, height: size.height,
                                      inset: Sketch.inset)
            .map { CGPoint(x: $0.x, y: $0.y) }
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(Figma.sheetBackground).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            guard let first = spots.first, let last = spots.last else { return }
            let path = UIBezierPath()
            path.move(to: first)
            spots.dropFirst().forEach { path.addLine(to: $0) }
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            UIColor.black.withAlphaComponent(0.55).setStroke()
            path.lineWidth = Sketch.outline
            path.stroke()
            UIColor(Figma.accentsGreen).setStroke()
            path.lineWidth = Sketch.line
            path.stroke()
            for (spot, color) in [(first, UIColor.white), (last, UIColor(Figma.accentsGreen))] {
                let rect = CGRect(x: spot.x - Sketch.dot / 2, y: spot.y - Sketch.dot / 2,
                                  width: Sketch.dot, height: Sketch.dot)
                UIColor.black.withAlphaComponent(0.7).setFill()
                UIBezierPath(ovalIn: rect.insetBy(dx: -2, dy: -2)).fill()
                color.setFill()
                UIBezierPath(ovalIn: rect).fill()
            }
        }
    }

    /// Пустой ли кадр: средняя яркость уменьшенной копии.
    static func isBlank(_ image: UIImage) -> Bool {
        let side = Sketch.probe
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let cgImage = image.cgImage,
              let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return false
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        let sum = stride(from: 0, to: pixels.count, by: 4).reduce(0) {
            $0 + Int(pixels[$1]) + Int(pixels[$1 + 1]) + Int(pixels[$1 + 2])
        }
        return CGFloat(sum) / CGFloat(side * side * 3 * 255) > Sketch.blank
    }
}

/// Кадры карт для карточек истории: в памяти и в папке кэша приложения.
/// Поездка не меняется, поэтому кадр не устаревает; систему не просим его
/// беречь — пропадёт, снимем заново.
@MainActor
enum TripSnapshots {
    private static let memory = NSCache<NSString, UIImage>()
    private static let folder = URL.cachesDirectory.appending(path: "trip-maps")

    private static func file(_ key: String) -> URL { folder.appending(path: key + ".jpg") }

    static func image(for key: String) -> UIImage? {
        if let hit = memory.object(forKey: key as NSString) { return hit }
        guard let image = UIImage(contentsOfFile: file(key).path) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    static func store(_ image: UIImage, for key: String, onDisk: Bool) {
        memory.setObject(image, forKey: key as NSString)
        guard onDisk, let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file(key), options: .atomic)
    }

    /// Поездку удалили — её кадр тоже: на нём маршрут.
    static func remove(for key: String) {
        memory.removeObject(forKey: key as NSString)
        try? FileManager.default.removeItem(at: file(key))
    }
}
