import PhotosUI
import SwiftData
import SwiftUI

/// Разделяет разряды пробелами, как в макете: «9 000 000 км».
func formattedNumber(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = "\u{00A0}"
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

/// Константы шапки при прокрутке. Вынесены из вью намеренно: замыкание
/// `visualEffect` помечено `@Sendable` и не может читать статики, изолированные
/// главным актором.
private enum ScrollHeader {
    static let space = "carScroll"

    /// Отрезок появления. Заголовок страницы стоит на 103 и высотой 31, шапка
    /// теперь 86 — значит он начинает уходить под неё на смещении 17 и полностью
    /// скрывается на 48. Раньше шапка проявлялась раньше, чем ей было что закрыть.
    static let fadeStart: CGFloat = 17
    static let fadeEnd: CGFloat = 48

    static func visibility(at offset: CGFloat) -> Double {
        Double(min(1, max(0, (offset - fadeStart) / (fadeEnd - fadeStart))))
    }
}

/// Пружина под фото машины: чем сильнее оттянут список, тем крупнее картинка.
/// Константы вне вью по той же причине, что и у `ScrollHeader`.
private enum PhotoStretch {
    /// Положение блока фото от верха контента в покое: 103 (отступ страницы)
    /// + заголовок 31.2 + 16 + номер 32 + 24. Из текущего положения вычитается
    /// это — разница и есть натяжка. Ошибка в константе видна сразу: фото
    /// окажется увеличенным уже в покое, поэтому она проверяется кадром.
    static let restingY: CGFloat = 206.2

    /// Прирост масштаба на точку натяжки и потолок роста.
    static let perPoint: CGFloat = 1 / 500
    static let maxGain: CGFloat = 0.35

    static func scale(pull: CGFloat) -> CGFloat {
        1 + min(max(0, pull) * perPoint, maxGain)
    }
}

/// Figma «раздел «машина»»: «главная» (45854:3547), «главная_то_добавлено» (45867:3007),
/// «добавление то» (45870:2868) и «сакцесс» (45887:3561).
struct CarMainView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var metrics: DeviceMetrics

    /// Машины из локальной базы. Карусель показывает первую — вёрстка макета
    /// рассчитана на одну машину плюс страницу «Добавить авто».
    @Query(sort: \Car.createdAt) private var cars: [Car]

    @State private var tab = 0
    @State private var carPage = 0
    @State private var dragX: CGFloat = 0
    /// Ось жеста фиксируется на первом заметном смещении и держится до конца.
    /// Раньше решение принималось на каждом кадре — отсюда дёрганье.
    @State private var swipeAxis: SwipeAxis?
    @State private var showServiceChoice = false
    @State private var showAddService = false
    @State private var showPhotoPicker = false
    @State private var showAddCar = false
    @State private var carTab = 0
    @State private var carPlate = ""
    @State private var carName = ""
    @State private var carMileage = ""
    /// Свой пикер у формы авто. Раньше она писала в общий photoItems, который
    /// слушает поток ТО, — выбор фото открывал чужую модалку и терялся.
    @State private var carPhotoItems: [PhotosPickerItem] = []
    @State private var newCarPhoto: UIImage?
    /// Раскодированный снимок текущей машины. Держим готовым: `body`
    /// пересобирается на каждом кадре свайпа, декодировать в нём нельзя.
    /// Раскодированные снимки машин. Держим готовыми: `body` пересобирается
    /// на каждом кадре свайпа, декодировать в нём нельзя.
    @State private var carImages: [PersistentIdentifier: UIImage] = [:]
    @State private var showToast = false
    /// Запись, которую сейчас правят. nil — значит шторка создаёт новую.
    @State private var editingRecord: ServiceRecord?
    @State private var toastMessage = "ТО добавлено!"
    /// Таймер скрытия. Хранится, чтобы его можно было отменить: без этого
    /// таймер предыдущего тоста гасил следующий почти сразу после появления.
    @State private var toastTask: Task<Void, Never>?
    /// Счётчик добавленных ТО. Именно он, а не `services.count`, запускает
    /// отклик успеха: число ТО принадлежит текущей машине и меняется при
    /// свайпе между машинами с разной историей — поверх отклика карусели
    /// прилетал чужой «успех», и перелистывание ощущалось по-разному.
    /// Удаление записи по той же причине больше не отдаёт «успех».
    @State private var addedServiceTick = 0

    @State private var showDeleteConfirm = false
    /// Модалка раздела «Ошибки» накрывает экран целиком, включая таббар.
    @State private var hidesTabBar = false
    /// Смещение прокрутки заполненной страницы. Управляет двумя вещами:
    /// запретом свайпа карусели и появлением шапки.
    ///
    /// Живёт в ссылочной коробке, а не в `@State`, и это не украшательство:
    /// значение пишется на каждом кадре прокрутки. Через `@State` от него
    /// начинал зависеть `body`, `ScrollView` пересобирался на каждом кадре,
    /// и экран сам уезжал вниз на 151pt — шапка «появлялась» в покое.
    /// Коробку никто не наблюдает, поэтому запись в неё ничего не перерисовывает.
    private final class ScrollState {
        var offset: CGFloat = 0
        /// Живой UIScrollView под SwiftUI-прокруткой. Нужен, чтобы гасить
        /// вертикаль на время горизонтального свайпа, не трогая состояние.
        weak var view: UIScrollView?
    }
    @State private var scroll = ScrollState()

    /// Свёрнутость таббара. В `@State` лежит только ссылка — экран на объект
    /// не подписан, иначе прокрутка снова начала бы пересобирать `body`.
    /// Подписан сам `FloatingTabBar`; см. комментарий у `TabBarState`.
    /// Нужен только ветке iOS 17–25: на 26 сворачиванием занимается система.
    @State private var tabBar = TabBarState()

    /// Гасим сам распознаватель, а не `isScrollEnabled`: последним управляет
    /// SwiftUI из окружения и может перезаписать его на любом обновлении, а
    /// `body` во время свайпа пересобирается каждый кадр из-за `dragX`.
    /// Профиль отказа при этом правильный: если правку всё-таки затрут,
    /// вернётся нынешнее поведение, а не мёртвая прокрутка.
    private func setScrollEnabled(_ enabled: Bool) {
        scroll.view?.panGestureRecognizer.isEnabled = enabled
    }


    /// Тот же поставщик, что и на первом экране добавления.
    private let lookup: any VehicleLookup = StubVehicleLookup()

    /// Межсервисный интервал: ТО через 10 000 км от последнего.
    private let serviceInterval = 10_000

    /// Индекс страницы добавления: она всегда последняя, после всех машин.
    private var addPageIndex: Int { cars.count }

    /// Непрерывное положение карусели, 0…addPageIndex. Ширина взята
    /// постоянной: карусель равна ширине экрана, а точность здесь нужна лишь
    /// чтобы поймать середину свайпа. Реальная ширина остаётся у порогов жеста.
    private var position: Double {
        min(Double(addPageIndex),
            max(0, Double(CGFloat(carPage) - dragX / Figma.frameWidth)))
    }

    /// Вклад страницы в то, что сейчас на экране: 1 — мы ровно на ней,
    /// 0 — дальше соседней. Этим перекрёстно гаснут названия и номера.
    private func weight(of page: Int) -> Double {
        max(0, 1 - abs(position - Double(page)))
    }

    private func index(of car: Car) -> Int {
        cars.firstIndex(where: { $0.persistentModelID == car.persistentModelID }) ?? 0
    }

    /// Ближайшая страница — по ней подсвечена точка и ей принадлежит тело.
    private var nearestPage: Int { Int(position.rounded()) }

    /// Насколько мы на странице добавления. Всё, что было завязано на прежний
    /// прогресс 0…1, продолжает работать без правок: он по-прежнему 0 на
    /// машинах и 1 на последней странице.
    private var addProgress: Double {
        min(1, max(0, position - Double(addPageIndex - 1)))
    }

    /// Машина, которой принадлежит тело экрана. Меняется ровно на середине
    /// свайпа — там, где обе надписи наполовину прозрачны и подмена не видна.
    /// Аннотация макета 45895:3569 — «все элементы остаются на месте и просто
    /// меняются надписи», поэтому страница неподвижна, едет только фото.

    private enum SwipeAxis { case horizontal, vertical }

    /// Порог, после которого решаем, куда ведёт жест.
    private static let axisLockThreshold: CGFloat = 10

    /// Высота зоны свайпа от верха экрана: отступ страницы 103 + шапка 349
    /// + гэп 20 + карточка «ТО через» 146.
    private static let swipeZoneHeight: CGFloat = 620

    /// Дальше этого смещения список считается прокрученным и карусель
    /// запирается. Порог небольшой: он должен пропускать дрожание пальца,
    /// но не реальную прокрутку.
    private static let swipeLockOffset: CGFloat = 8

    /// Карусель листается только в верхней зоне — по фото машины и карточке
    /// «ТО через» — и только пока список не прокручен. Ниже и в прокрутке
    /// жест не наш, поэтому конфликтов с вертикальным скроллом и лентой ТО нет.
    /// startLocation даёт зону без оверлея, то есть не трогая нажатия по
    /// карточкам и кнопкам внутри неё.
    private func canSwipe(startY: CGFloat) -> Bool {
        startY < Self.swipeZoneHeight && scroll.offset < Self.swipeLockOffset
    }

    private func carouselDrag(width: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard canSwipe(startY: value.startLocation.y) else { return }
                let dx = value.translation.width
                let dy = value.translation.height

                // Начало нового жеста: смещение ещё крошечное, а ось осталась
                // с прошлого раза — значит onEnded не пришёл, сбрасываем.
                if max(abs(dx), abs(dy)) < 2 {
                    swipeAxis = nil
                    setScrollEnabled(true)
                }

                if swipeAxis == nil,
                   max(abs(dx), abs(dy)) > Self.axisLockThreshold {
                    swipeAxis = abs(dx) > abs(dy) ? .horizontal : .vertical
                    // Касание получают оба — наш жест и UIScrollView. Пока
                    // мы не выключали ему панорамирование, он честно отматывал
                    // список на вертикальную составляющую пальца: свайп
                    // сопровождался микроскроллом вверх, а дрейф больше 8pt
                    // ещё и запирал карусель для следующего свайпа.
                    setScrollEnabled(swipeAxis != .horizontal)
                }
                guard swipeAxis == .horizontal else { return }

                // За краями страницы нет. Любая подложка под каруселью
                // давала артефакты (раздувала вьюпорт, проступала из-под
                // контента), поэтому вместо неё резинка сделана совсем
                // короткой — обнажается лишь пара точек, отдача есть,
                // а фона за краем не видно.
                let atEdge = (carPage == 0 && dx > 0)
                    || (carPage == addPageIndex && dx < 0)
                dragX = atEdge ? dx / 10 : dx
            }
            .onEnded { value in
                // Первым делом и без условий: залипший запрет прокрутки —
                // ровно та авария, которую журнал уже описывает.
                setScrollEnabled(true)

                let axis = swipeAxis
                swipeAxis = nil

                // Жест мог начаться разрешённым и стать запрещённым посреди
                // движения: список успел уехать за порог. Тогда dragX залипнет
                // и страница останется наполовину погашенной — возвращаем.
                guard axis == .horizontal, canSwipe(startY: value.startLocation.y) else {
                    if dragX != 0 { withAnimation(Motion.page) { dragX = 0 } }
                    return
                }

                let threshold = width * 0.22
                var page = carPage
                if value.translation.width < -threshold { page = min(addPageIndex, carPage + 1) }
                if value.translation.width > threshold { page = max(0, carPage - 1) }
                withAnimation(Motion.page) {
                    carPage = page
                    dragX = 0
                }
            }
    }

    private var car: Car? {
        let index = min(max(0, nearestPage), cars.count - 1)
        return cars.indices.contains(index) ? cars[index] : nil
    }
    private var services: [ServiceRecord] { car?.sortedServices ?? [] }
    private var odometer: Int { car?.odometer ?? 0 }

    // Поля шторки «Добавление ТО»
    @State private var serviceDate = Date()
    @State private var serviceMileage = ""
    @State private var works: [ServiceWork] = [ServiceWork()]
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photos: [UIImage] = []

    var body: some View {
        tabs
            // Шторки, тост и рамка висят **снаружи** таббара, а не внутри
            // вкладки. Внутри вкладки системный бар рисуется поверх её
            // содержимого, и шторка уходила бы под него.
            .overlay(alignment: .topLeading) { toastLayer }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .bottomSheet(isPresented: $showServiceChoice) {
            AddServiceChoiceSheet(
                onClose: { showServiceChoice = false },
                onPickPhoto: {
                    showServiceChoice = false
                    showPhotoPicker = true
                },
                onManual: {
                    showServiceChoice = false
                    showAddService = true
                }
            )
        }
        .bottomSheet(isPresented: $showAddService) {
            AddServiceSheet(
                title: editingRecord == nil ? "Добавление ТО" : "Изменение ТО",
                date: $serviceDate,
                mileage: $serviceMileage,
                works: $works,
                photoItems: $photoItems,
                photos: $photos,
                onClose: {
                    showAddService = false
                    // Иначе следующее «Добавить ТО» молча перезапишет запись
                    editingRecord = nil
                    clearServiceForm()
                },
                onSave: saveService
            )
            .padding(.top, 62)
        }
        .modifier(CarMainChrome(
            showAddCar: $showAddCar,
            showPhotoPicker: $showPhotoPicker,
            photoItems: $photoItems,
            carTab: $carTab,
            carPlate: $carPlate,
            carName: $carName,
            carMileage: $carMileage,
            carPhotoItems: $carPhotoItems,
            carPhoto: newCarPhoto,
            onCarPhotoLoaded: { newCarPhoto = $0 },
            onSubmitCar: addCar,
            onPhotosLoaded: { loaded in
                photos = loaded
                if !loaded.isEmpty { applyParsedService() }
            }
        ))
        // gradient bg (45879:3002): сам градиент лежит в контенте страницы и
        // уезжает вверх вместе со скроллом. База светлая — она видна снизу,
        // под контентом. Чёрное сверху даёт запас в gradientLayer.
        .background(Figma.mainBackground.ignoresSafeArea())
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        // «нативная штука добавления фото» (45885:3279) — системный пикер,
        // после выбора открываем форму с уже прикреплённым файлом.
        .animation(Motion.toast(reduceMotion: reduceMotion), value: showToast)
        .onChange(of: tab) { _, new in
            // Смещения прежнего раздела к новому отношения не имеют, а бар
            // должен встречать раздел развёрнутым.
            tabBar.reset()
            // Страховка: таббар прячет только шторка находок в «Ошибках».
            // Уход с раздела мимо неё оставлял бы бар скрытым навсегда.
            if new != 2 { hidesTabBar = false }
        }
        .sensoryFeedback(.success, trigger: addedServiceTick)
        // Декодирование вне главного актора, как и у чеков ТО
        .task(id: carPhotoKey) {
            var decoded: [PersistentIdentifier: UIImage] = [:]
            for car in cars {
                guard let data = car.photo else { continue }
                if let image = await ImageLoader.decode([data]).first {
                    decoded[car.persistentModelID] = image
                }
            }
            carImages = decoded
        }
        // Отклик при смене машины: мягкий удар, а не сухой щелчок пикера —
        // перелистывание карточки ощущается «мясистее». Срабатывает на
        // защёлкивании страницы, а не по ходу пальца: незасчитанный свайп
        // не меняет carPage и потому молчит.
        .sensoryFeedback(.impact(flexibility: .soft), trigger: carPage)
        .confirmationDialog("Удалить авто?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { deleteCar() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("История обслуживания тоже будет удалена.")
        }
    }

    // MARK: - Разделы

    /// На iOS 26 таббар берётся системный. Компонент в макете —
    /// «Tab Bar - iPhone» из дизайн-кита Apple, причём с вариантом `Minimized`:
    /// дизайн описывает именно системный элемент, поэтому правильный код —
    /// не повторять его руками, а взять. Своя реализация остаётся веткой для
    /// iOS 17–25, где этих API ещё нет.
    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 26.0, *) {
            systemTabs
        } else {
            legacyTabs
        }
    }

    @available(iOS 26.0, *)
    private var systemTabs: some View {
        TabView(selection: tabSelection) {
            Tab("Машина", systemImage: "car", value: 0) { carScreen.environment(\.colorScheme, .dark) }
            Tab("Карта", systemImage: "map", value: 1) { MapScreen().ignoresSafeArea().environment(\.colorScheme, .dark) }
            Tab("Ошибки", systemImage: "wrench.adjustable", value: 2) {
                IssuesScreen(hidesTabBar: $hidesTabBar)
                    .ignoresSafeArea()
                    .environment(\.colorScheme, .dark)
                    // Видимость бара объявляется **содержимым вкладки**, а не
                    // самим `TabView`: на `TabView` модификатор молча
                    // игнорируется, и бар оставался поверх модалки.
                    .toolbarVisibility(hidesTabBar ? .hidden : .automatic, for: .tabBar)
            }
            Tab("Ещё", systemImage: "ellipsis", value: 3) { MoreScreen().ignoresSafeArea().environment(\.colorScheme, .dark) }
        }
        // Бар в макете объявлен светлым (`BG mode="Light"`), а экран идёт в
        // тёмной схеме ради светлого статус-бара. Схему задаём только бару;
        // разделы возвращают себе тёмную сами — каждый в своей вкладке.
        .environment(\.colorScheme, .light)
        // Без своего цвета выбранная вкладка выходила **тусклее** невыбранных:
        // системный бар красит её акцентом, а по умолчанию он не читается на
        // стекле. Синий — цвет выбранной вкладки из макета.
        .tint(Figma.accentsBlue)
        // Сворачивание при прокрутке вниз — то самое, что раньше считалось
        // руками в TabBarState с порогом в 28pt.
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    /// Повторный тап по активной вкладке система сама обрабатывает только
    /// внутри `NavigationStack`; у нас списки свои, поэтому ловим здесь.
    private var tabSelection: Binding<Int> {
        Binding(get: { tab },
                set: { new in
                    if new == tab { scrollToTop() } else { tab = new }
                })
    }

    /// iOS 17–25: прежняя раскладка со своим баром поверх содержимого.
    private var legacyTabs: some View {
        ZStack(alignment: .topLeading) {
            switch tab {
            case 1: MapScreen().ignoresSafeArea().transition(tabTransition)
            case 2: IssuesScreen(hidesTabBar: $hidesTabBar)
                    .ignoresSafeArea().transition(tabTransition)
            case 3: MoreScreen().ignoresSafeArea().transition(tabTransition)
            default: carScreen.transition(tabTransition)
            }

            // В макете таббар стоит на y = 779 при высоте экрана 874, то есть
            // в 7pt над home indicator. Прижимаем к нижней safe area, чтобы
            // этот зазор сохранялся на экранах любой высоты.
            FloatingTabBar(selection: $tab, state: tabBar, onReselect: { _ in scrollToTop() })
                .opacity(hidesTabBar ? 0 : 1)
                .allowsHitTesting(!hidesTabBar)
                .frame(maxWidth: .infinity)
                .offset(y: metrics.bottomAnchoredY(designY: 779, height: 54))
        }
    }

    // MARK: - Страница машины

    /// Карусель авто: интерактивный пейджинг свайпом влево/вправо.
    /// Аннотация макета (45895:3569): «все элементы остаются на месте и просто
    /// меняются надписи» — раскладка страниц идентична, разъезжаться нечему.
    private var carScreen: some View {
        GeometryReader { geo in
            let width = geo.size.width
            // Прогресс страницы добавления, 0…1. Страница НЕ едет: он
            // управляет только содержимым — текстами и видимостью блоков.
            let p = addProgress

            carPageBody(progress: p)
                // simultaneousGesture, а не gesture: заполненная страница —
                // вертикальный ScrollView, и он забирал свайп себе, поэтому
                // над картинкой машины и карточкой ТО карусель не листалась.
                .simultaneousGesture(carouselDrag(width: width))
        }
        // важно: сам GeometryReader должен игнорировать safe area, иначе он
        // отдаёт урезанный размер и все координаты макета съезжают вниз
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var toastLayer: some View {
        if showToast {
            toast
                .frame(maxWidth: .infinity)
                .offset(y: 62)
                .transition(toastTransition)
                // HIG: временное сообщение не перехватывает работу с
                // экраном — под ним всё остаётся нажимаемым.
                .allowsHitTesting(false)
        }
    }

    /// Величины, которыми раскладка одной страницы отличается от другой.
    /// Их четыре, и все они числа — поэтому смешиваются, а не переключаются.
    /// Из-за переключения на середине свайпа предыдущая версия и выглядела
    /// сломанной.
    private struct PageMetrics {
        var headerGap: CGFloat = 20
        /// Натуральная высота содержимого «ТО через»: 13pt + 4 + 28pt + 12 +
        /// полоса 30 плюс паддинги 48. Макет объявляет 146 — расхождение из-за
        /// метрик шрифта, оно было и раньше. Здесь важно повторить то, что
        /// экран рисовал до правки, а не «починить» заодно и это.
        var cardHeight: CGFloat = 142.9
        var statsGap: CGFloat = 16
        /// 0 — истории нет, 1 — есть. Дробное значение живёт только в движении.
        var history: Double = 1

        static func + (a: PageMetrics, b: PageMetrics) -> PageMetrics {
            PageMetrics(headerGap: a.headerGap + b.headerGap,
                        cardHeight: a.cardHeight + b.cardHeight,
                        statsGap: a.statsGap + b.statsGap,
                        history: a.history + b.history)
        }

        static func * (m: PageMetrics, k: Double) -> PageMetrics {
            PageMetrics(headerGap: m.headerGap * k, cardHeight: m.cardHeight * k,
                        statsGap: m.statsGap * k, history: m.history * k)
        }
    }

    /// Величины страницы. У машины — по её состоянию (ноды 45854:3547 и
    /// 45867:3007), у страницы добавления — как у последней машины: переход
    /// к ней и так гладкий, двигать там нечего.
    private func metrics(of page: Int) -> PageMetrics {
        let index = min(max(0, page), cars.count - 1)
        guard cars.indices.contains(index) else { return PageMetrics() }
        return cars[index].services.isEmpty
            ? PageMetrics(headerGap: 24, cardHeight: 92, statsGap: 24, history: 0)
            : PageMetrics()
    }

    /// Веса двух соседних страниц дают в сумме 1, поэтому это именно смесь.
    private var blended: PageMetrics {
        var result = PageMetrics(headerGap: 0, cardHeight: 0, statsGap: 0, history: 0)
        for page in 0...addPageIndex {
            let w = weight(of: page)
            if w > 0 { result = result + metrics(of: page) * w }
        }
        return result
    }

    /// Высота блока истории (нода 45893:3541). Она не зависит от числа записей:
    /// лента прокручивается по горизонтали. Константа нужна, чтобы блок
    /// сворачивался плавно; ошибка в ней видна в покое щелью или обрезкой.
    private static let historyHeight: CGFloat = 350

    private func carPageBody(progress p: Double) -> some View {
        let visible = 1 - p
        let m = blended

        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header(progress: p, stretches: true)

                Spacer(minLength: 0).frame(height: m.headerGap)

                // На второй странице карточка превращается в кнопку
                // добавления авто; на машине это сводка или «Добавить ТО».
                Button {
                    if p > 0.5 { showAddCar = true } else if services.isEmpty { showServiceChoice = true }
                } label: {
                    darkCard(progress: p, height: m.cardHeight)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(p > 0.5 ? "Добавить авто" : "ТО")

                Spacer(minLength: 0).frame(height: m.statsGap)

                // Белые карточки уходят целиком: на странице «добавить новую»
                // (нода 45949:3265) их нет вовсе, остаётся одна тёмная.
                HStack(spacing: 16) {
                    statCard(title: "Цена авто") { _ in "4 269 999 ₽ " }
                    statCard(title: "Пробег") { "\(formattedNumber($0.odometer)) км " }
                }
                .opacity(visible)

                // Зазор сворачивается вместе с историей, иначе у машины без ТО
                // остался бы двойной отступ до «Удалить авто».
                Spacer(minLength: 0).frame(height: 32 * m.history)

                historyCard()
                    .frame(height: Self.historyHeight * m.history, alignment: .top)
                    .clipped()
                    .opacity(visible * m.history)
                    // Погашенная вьюха продолжает принимать касания —
                    // иначе «Добавить ТО» внутри неё нажимается вслепую.
                    .allowsHitTesting(visible * m.history > 0.5)

                Spacer(minLength: 0).frame(height: 32)

                deleteButton()
                    .opacity(visible)
                    .allowsHitTesting(visible > 0.5)
            }
            .padding(.horizontal, 16)
            .padding(.top, 103)
            .padding(.bottom, 140)
            .background(alignment: .top) { gradientLayer }
            // Позиция прокрутки для запрета свайпа. Именно `.background` —
            // слой не участвует в раскладке и не может раздуть страницу,
            // как когда-то градиент.
            .background { scrollOffsetReader }
            .background {
                ScrollViewFinder { found in
                    scroll.view = found
                    found.panGestureRecognizer.isEnabled = true
                }
            }
            // Шапка лежит внутри прокрутки и приколочена к верху обратным
            // сдвигом. Оверлей не занимает места в раскладке.
            .overlay(alignment: .top) { scrollHeader(progress: p) }
        }
        .coordinateSpace(name: ScrollHeader.space)
        // На странице «Добавить авто» белые карточки погашены, но место
        // занимают, а у машины без ТО прокручивать нечего — в обоих случаях
        // прокрутка открывала бы пустоту. Флаг считается из carPage и dragX,
        // залипнуть не может.
        .scrollDisabled(p > 0.5 || services.isEmpty)
        // HIG: форму со списком клавиатура должна отпускать скроллом
        .scrollDismissesKeyboard(.interactively)
    }

    /// iOS 17 не умеет `onScrollGeometryChange`, поэтому позиция снимается
    /// геометрией контента в именованном пространстве координат ScrollView.
    private var scrollOffsetReader: some View {
        GeometryReader { g in
            let offset = -g.frame(in: .named(ScrollHeader.space)).minY
            Color.clear
                .onAppear { scroll.offset = offset }
                .onChange(of: offset) { _, new in
                    scroll.offset = new
                    // Свёрнутость таббара считается здесь же и по тем же
                    // правилам, что и запрет свайпа: отдельного наблюдателя
                    // прокрутки заводить незачем.
                    tabBar.track(offset: new)
                }
        }
    }

    /// HIG: повторный тап по активной вкладке возвращает раздел в начало.
    /// Работаем через живой `UIScrollView` — тот же, которому глушим
    /// панорамирование на свайпе карусели: `ScrollViewReader` потребовал бы
    /// якорь в контенте и ещё одно состояние.
    private func scrollToTop() {
        guard let view = scroll.view else { return }
        let top = -view.adjustedContentInset.top
        guard view.contentOffset.y > top else { return }
        view.setContentOffset(CGPoint(x: 0, y: top), animated: true)
    }

    /// Разделы меняются растворкой: вкладки — не соседние страницы, а разные
    /// места приложения, и уезжающий вбок контент подсказывал бы неверное.
    /// Так же переключает разделы `TabView` в iOS 26. Приходящий чуть
    /// подрастает, уходящий просто гаснет — движение остаётся у входа.
    private var tabTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97)),
            removal: .opacity
        )
    }

    // MARK: - Шапка при прокрутке

    /// Figma «header» (46012:1815): чёрная плашка 402×86 поверх статус-бара,
    /// контент прижат к низу. Только название — номера в новой ноде нет.
    private func scrollHeader(progress p: Double) -> some View {
        // Высота 20 (leading/subheadline) вместо figmaLineHeight: строка одна,
        // и Figma центрирует её в line box — то же делает фиксированная высота.
        // Трекинга нет: токен Subheadline объявляет −0.23, но нода отрисована
        // без него — ширина чернил на рендере 182pt против 178 с трекингом.
        // Та же история была у прошлой шапки, проверять замером обязательно.
        Text(car?.name ?? "")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(height: 20)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
        .frame(height: Figma.scrollHeaderHeight, alignment: .bottom)
        .background(Figma.graysBlack)
        // Шапка декоративная: касания должны доходить до контента под ней
        .allowsHitTesting(false)
        // Обратный сдвиг держит шапку у верха экрана, а прозрачность растёт
        // по мере ухода контента под неё. Множитель (1 - p) убирает название
        // текущей машины на странице «Добавьте новый авто».
        //
        // visualEffect — эффект этапа отрисовки: он читает геометрию, не
        // превращая её в состояние. Через `@State` то же самое пересобирало
        // ScrollView на каждом кадре прокрутки, и экран уезжал сам.
        .visualEffect { content, proxy in
            let offset = -proxy.frame(in: .named(ScrollHeader.space)).minY
            return content
                .offset(y: offset)
                .opacity(ScrollHeader.visibility(at: offset) * (1 - p))
        }
    }


    /// Градиентный слой под контентом: 934pt от верха. Именно `.background`,
    /// иначе слой увеличил бы высоту страницы и контент бы отцентрировался.
    private var gradientLayer: some View {
        VStack(spacing: 0) {
            // Запас на оттягивание сверху: ScrollView обрезает по своим
            // границам, поэтому чёрное видно только когда список тянут вниз.
            Color.black
                .frame(height: Self.overscrollReserve)

            Figma.mainGradient
                .frame(height: Figma.mainGradientHeight)

            // Ниже градиента продолжаем его нижним цветом, иначе на длинном
            // контенте появлялся шов между градиентом и фоном экрана.
            Figma.mainBackground
        }
        .frame(maxWidth: .infinity)
        // сдвигаем вверх, чтобы сам градиент начинался ровно у верха контента
        .offset(y: -Self.overscrollReserve)
    }

    private static let overscrollReserve: CGFloat = 600

    // MARK: - Шапка: название, номер, фото, пейдж-контрол

    /// `stretches` включает пружину. На экране без ТО прокрутки нет, а
    /// пространства координат `ScrollHeader.space` не существует вовсе —
    /// `frame(in:)` по неизвестному имени вернул бы мусор.
    private func header(progress p: Double, stretches: Bool) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 24) {
                // Заголовок и номер стоят на месте, текст перекрёстно меняется
                VStack(spacing: 16) {
                    ZStack {
                        ForEach(cars) { car in
                            title(car.name).opacity(weight(of: index(of: car)))
                        }
                        title("Добавьте новый авто").opacity(weight(of: addPageIndex))
                    }

                    ZStack {
                        ForEach(cars) { car in
                            plate(car.plate).opacity(weight(of: index(of: car)))
                        }
                    }
                    .frame(height: 32)
                }

                // Единственный едущий элемент. Локальный GeometryReader
                // намеренно: он принимает предложенную ширину контентной
                // области (370), а не экранную. Раньше здесь стояла
                // width * 2 от ширины экрана, и вся раскладка вылезала
                // за края на 16pt с каждой стороны.
                GeometryReader { g in
                    HStack(spacing: 0) {
                        ForEach(cars) { car in
                            carPhoto(for: car).frame(width: g.size.width)
                        }
                        // Страница добавления: у неё своей машины нет
                        carPhoto(for: nil).frame(width: g.size.width)
                    }
                    .offset(x: -CGFloat(position) * g.size.width)
                }
                .frame(height: 190.415)
                .clipped()
                // Масштаб навешен ПОСЛЕ .clipped(): эффект применяется к уже
                // обрезанному результату, поэтому вторая копия фото из-под
                // клипа не вылезает.
                //
                // visualEffect, а не @State: геометрия читается на этапе
                // отрисовки и не пересобирает ScrollView — см. журнал.
                .visualEffect { content, proxy in
                    let pull = stretches
                        ? proxy.frame(in: .named(ScrollHeader.space)).minY - PhotoStretch.restingY
                        : 0
                    return content.scaleEffect(PhotoStretch.scale(pull: pull), anchor: .center)
                }
            }

            pageControl
        }
    }

    /// Одно место на весь экран: то же название стоит и в шапке при прокрутке.
    /// TODO: брать из модели, когда появится справочник марок.
    private static let carTitle = "Mercedes-Benz GL-класс"

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 26, weight: .bold))
            .figmaLineHeight(31.2, fontSize: 26, weight: .bold)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    /// Снимок машины, если он есть, иначе макетный ассет. `scaledToFit`
    /// намеренно: кадр из галереи бывает любой пропорции, и обрезать его по
    /// рамке макета — значит отрезать пользователю его же машину.
    private func carPhoto(for car: Car?) -> some View {
        Group {
            if let car, let image = carImages[car.persistentModelID] {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image("CarPhoto").resizable().scaledToFit()
            }
        }
        .frame(width: 295.736, height: 152.196)
        .frame(maxWidth: .infinity)
    }

    /// Ключ перезагрузки: меняется и при смене машины, и при замене снимка.
    /// Сам `Data` в качестве id брать нельзя — сравнивать блоб на каждом
    /// обновлении вью бессмысленно дорого.
    private var carPhotoKey: String {
        cars.map { "\($0.persistentModelID.hashValue)-\($0.photo?.count ?? 0)" }
            .joined(separator: "|")
    }

    /// Номер разбирается на группы «В 777 ОР | 777». У машины, добавленной
    /// по названию, номера нет вовсе — тогда плашки просто не будет.
    @ViewBuilder
    private func plate(_ raw: String) -> some View {
        let parts = raw.split(separator: " ").map(String.init)
        if parts.count == 4 {
            HStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(parts[0])
                    Text(parts[1])
                    Text(parts[2])
                }

                Rectangle()
                    .fill(Figma.separatorsVibrant)
                    .frame(width: 1, height: 20.117)
                    .blendMode(.softLight)

                Text(parts[3])
            }
            .font(.system(size: 17, weight: .semibold))
            .tracking(-0.43)
            .foregroundStyle(Figma.graysGray2)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(height: 32)
            .background(Figma.fillsPrimary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var pageControl: some View {
        HStack(spacing: 8) {
            // Точка не исчезает, а гаснет до Fills/Primary
            ForEach(cars) { car in
                Circle()
                    .fill(nearestPage == index(of: car) ? .white : Figma.fillsPrimary)
                    .frame(width: 8, height: 8)
            }

            incrementGlyph(active: nearestPage == addPageIndex)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlass(in: Capsule()) { Capsule().fill(Color.white.opacity(0.07)) }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }

    /// «Increment» из Page Control: тонкий плюс. На странице добавления он активен
    /// (белый), на главной — тусклый, как неактивная точка.
    private func incrementGlyph(active: Bool) -> some View {
        // одной фигурой, а не двумя капсулами: у пересечения не должна
        // складываться прозрачность
        PlusGlyph()
            .fill(active ? Color.white : Color.white.opacity(0.12))
            .frame(width: 9.5, height: 9.5)
            .frame(width: 8, height: 8)
    }

    // MARK: - Карточки


    /// Содержимое кнопки добавления (нода 45949:3290): плюс, гэп 10, подпись
    /// 17pt semibold. Плюс один на оба состояния — он одинаков, а перекрёстное
    /// гашение двух копий давало бы на середине лишнюю яркость.
    private func addLabel(_ title: String, altTitle: String? = nil,
                          progress: Double = 0) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            ZStack {
                Text(title).opacity(altTitle == nil ? 1 : 1 - progress)
                if let altTitle { Text(altTitle).opacity(progress) }
            }
            .font(.system(size: 17, weight: .semibold))
            .tracking(-0.43)
            .foregroundStyle(.white)
        }
    }

    /// Единственная тёмная карточка экрана. Содержимое перекрёстно меняется
    /// между страницами, высота приходит смешанной — поэтому при свайпе она
    /// не подменяется, а перетекает.
    private func darkCard(progress p: Double, height: CGFloat) -> some View {
        ZStack {
            ForEach(cars) { car in
                Group {
                    if car.services.isEmpty {
                        addLabel("Добавить ТО")
                    } else {
                        serviceProgressContent(for: car)
                    }
                }
                .opacity(weight(of: index(of: car)))
            }

            addLabel("Добавить авто").opacity(weight(of: addPageIndex))
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        // Когда история на месте целиком, высоту задаёт содержимое — так
        // карточка в покое остаётся ровно такой, какой была. Смешанное
        // значение включается только в движении, где важна плавность,
        // а не попадание в пиксель.
        .frame(height: height >= PageMetrics().cardHeight ? nil : height)
        // Figma 45867:2944 — системный «Liquid Glass - Regular - Medium».
        // Кромку даёт стекло, а не нарисованная обводка; раньше здесь
        // расходились радиусы заливки (36) и обводки (34).
        .liquidGlass(in: RoundedRectangle(cornerRadius: 36), tint: Figma.darkCard, kind: .painted) {
            RoundedRectangle(cornerRadius: 36)
                .fill(Figma.darkCard)
                .overlay(RoundedRectangle(cornerRadius: 36)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5))
        }
        .motionRim(in: RoundedRectangle(cornerRadius: 36))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
    }

    private func serviceProgressContent(for car: Car) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("ТО через")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.08)
                    .foregroundStyle(Figma.vibrantPrimary)

                Text("\(formattedNumber(kmUntilService(for: car))) км ")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(0.38)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Figma.trackBackground)

                    RoundedRectangle(cornerRadius: 24)
                        .fill(Figma.accentsGreen)
                        .frame(width: geo.size.width * serviceProgress(for: car))
                }
            }
            .frame(height: 30)
        }
    }

    /// Значение перекрёстно меняется между машинами, подложка рисуется один
    /// раз: две белые карточки поверх друг друга дали бы на середине свайпа
    /// пересвет.
    private func statCard(title: String, value: @escaping (Car) -> String) -> some View {
        statCardShell(title: title) {
            ZStack {
                ForEach(cars) { car in
                    Text(value(car)).opacity(weight(of: index(of: car)))
                }
            }
        }
    }

    private func statCard(title: String, value: String) -> some View {
        statCardShell(title: title) { Text(value) }
    }

    /// Скругление плитки счётчика. Общая константа, потому что форма нужна и
    /// материалу, и его подложке — разъехавшись, они дали бы двойную кромку.
    private static let statCardShape = RoundedRectangle(cornerRadius: 34,
                                                        style: .continuous)

    private func statCardShell<V: View>(title: String,
                                        @ViewBuilder value: () -> V) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.08)
                .foregroundStyle(Figma.vibrantSecondary)

            Spacer(minLength: 0)

            value()
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.45)
                .foregroundStyle(Figma.labelsPrimary)
        }
        .frame(height: 47)
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        // В макете это «Liquid Glass - Regular - Small» (45895:3528), а не
        // белая плитка: на устройстве материал преломляет то, что под ним.
        // Тень из макета (0/0/32 #EBEBEB) остаётся — стекло её не заменяет.
        .liquidGlass(in: Self.statCardShape, tint: .white) {
            Self.statCardShape.fill(.white)
        }
        .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
    }

    /// История обслуживания. Белая подложка снята: блок лежит прямо на фоне
    /// страницы, поэтому и внутренний отступ 16 ушёл вместе с ней — иначе
    /// содержимое было бы на 32pt уже остальной страницы.
    private func historyCard() -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                VStack(spacing: 24) {
                    Text("История обслуживания")
                        .font(.system(size: 22, weight: .bold))
                        .figmaLineHeight(28, fontSize: 22, weight: .bold)
                        .foregroundStyle(Figma.labelsPrimary)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 16) {
                        statCard(title: "Всего потрачено", value: totalSpent)
                        statCard(title: "Количество ТО", value: "\(services.count)")
                    }
                }

                historyStrip
            }

            // «Добавить ТО» — синяя, на Fills/Tertiary
            Button { showServiceChoice = true } label: {
                Text("Добавить ТО")
                    .font(.system(size: 17))
                    .tracking(-0.43)
                    .foregroundStyle(Figma.accentsBlue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Figma.fillsTertiary, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// Лента карточек ТО 230×84; следующая карточка выглядывает справа.
    private var historyStrip: some View {
        // ScrollView клипует контент, поэтому даём тени запас внутри
        // и компенсируем его отрицательным отступом снаружи.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(services) { record in
                    serviceCard(record)
                        // HIG: действия над конкретным элементом — контекстное
                        // меню. Подъём карточки и хаптик даёт сама система,
                        // добавлять sensoryFeedback не нужно.
                        .contextMenu {
                            Button { startEditing(record) } label: {
                                Label("Изменить", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                // Работы уходят каскадом — правило в модели
                                modelContext.delete(record)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        } preview: {
                            // Своё превью, а не подъём оригинала: у карточки
                            // тень нарисована за пределами её формы, а лента
                            // компенсирует её отрицательным отступом. Границы
                            // снимка не совпадали с формой, и касание давало
                            // сжатие-отскок не по той геометрии.
                            serviceCardBody(record)
                                .frame(width: 230, height: 84)
                                .background(RoundedRectangle(cornerRadius: 34).fill(.white))
                        }
                }
            }
            .padding(shadowInset)
        }
        .frame(height: 84 + shadowInset * 2)
        .padding(-shadowInset)
    }

    private func serviceCard(_ record: ServiceRecord) -> some View {
        serviceCardBody(record)
            .frame(width: 230, height: 84)
            .background(
                RoundedRectangle(cornerRadius: 34)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
            )
    }

    /// Содержимое карточки без подложки: одно и то же рисуют лента и превью
    /// контекстного меню, поэтому оно вынесено.
    private func serviceCardBody(_ record: ServiceRecord) -> some View {
        VStack(spacing: 6) {
            Text(record.date, format: .dateTime.day(.twoDigits)
                .month(.twoDigits).year())
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.23)
                .foregroundStyle(Figma.vibrantControlsPrimary)

            HStack(spacing: 4) {
                Text("\(formattedNumber(record.mileage)) км ")
                Circle()
                    .fill(Figma.vibrantSecondary)
                    .frame(width: 4, height: 4)
                Text("\(formattedNumber(record.amount)) ₽ ")
            }
            .font(.system(size: 13))
            .tracking(-0.08)
            .foregroundStyle(Figma.vibrantSecondary)
        }
        .padding(20)
    }

    /// Запас вокруг ленты, чтобы тени карточек не обрезались.
    private let shadowInset: CGFloat = 16

    /// Деструктивное действие — по HIG требует подтверждения.
    private func deleteButton() -> some View {
        Button(role: .destructive) { showDeleteConfirm = true } label: {
            Text("Удалить авто")
                .font(.system(size: 17))
                .tracking(-0.43)
                .foregroundStyle(Figma.accentsRed)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Figma.fillsQuaternary, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Удалить авто")
    }

    /// Приход — пружиной сверху с проявлением. Уход — только затухание с
    /// лёгким уменьшением: сообщение отступает, а не улетает, и не тянет на
    /// себя взгляд, когда человек уже вернулся к экрану.
    ///
    /// При Reduce Motion движения нет вовсе, остаётся перекрёстное проявление —
    /// этого HIG требует прямо.
    private var toastTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }

        return .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
                .combined(with: .scale(scale: 0.96))
                .animation(Motion.toastOut)
        )
    }

    /// Показ тоста одним местом: сообщение, отмена прошлого таймера и
    /// объявление для VoiceOver, который иначе не узнал бы о нём вовсе.
    private func presentToast(_ message: String) {
        toastMessage = message
        toastTask?.cancel()
        showToast = true
        AccessibilityNotification.Announcement(message).post()

        toastTask = Task {
            try? await Task.sleep(for: Motion.toastDwell)
            guard !Task.isCancelled else { return }
            showToast = false
        }
    }

    /// Figma «сакцесс» → «Notification - Collapsed», аннотация «Хаптик позитивное действие».
    private var toast: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(Figma.accentsGreen)

            Text(toastMessage)
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.23)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 202)
        // Тот же системный Liquid Glass, что у карточек: кромку даёт стекло,
        // а не нарисованная обводка. Блик так же следует за наклоном.
        .liquidGlass(in: RoundedRectangle(cornerRadius: 24), tint: Figma.darkCard) {
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.black.opacity(0.8))
                        .blendMode(.luminosity)
                )
                .overlay(RoundedRectangle(cornerRadius: 24)
                    .stroke(Color(white: 217 / 255), lineWidth: 0.5))
        }
        .motionRim(in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.02), radius: 7.5, y: 8)
    }

    // MARK: - Действия

    private var totalSpent: String {
        "\(formattedNumber(services.map(\.amount).reduce(0, +))) ₽"
    }

    /// Пробег на последнем ТО — от него отсчитывается интервал.
    private func lastServiceMileage(for car: Car) -> Int {
        car.services.map(\.mileage).max() ?? car.odometer
    }

    /// «ТО через N км» — остаток до следующего сервиса.
    private func kmUntilService(for car: Car) -> Int {
        max(0, lastServiceMileage(for: car) + serviceInterval - car.odometer)
    }

    /// Прогресс интервала: сколько из 10 000 км уже проехали.
    private func serviceProgress(for car: Car) -> Double {
        let driven = Double(car.odometer - lastServiceMileage(for: car))
        return min(1, max(0, driven / Double(serviceInterval)))
    }

    /// Разбор фото/PDF: скрипт достаёт базовые показатели и форма открывается
    /// уже заполненной — ручной ввод с нуля здесь неуместен.
    /// TODO: заменить заглушку на реальный парсер.
    private func applyParsedService() {
        serviceDate = Date()
        serviceMileage = "\(odometer)"
        works = [ServiceWork(title: "Замена масла", amount: "12000")]
        showAddService = true
    }

    /// Создаёт машину из формы «Добавить авто». Раньше onSubmit только
    /// закрывал шторку, и всё введённое выбрасывалось.
    ///
    /// Подтверждения «Это ваш автомобиль?» здесь нет намеренно: на первом
    /// экране оно уточняет найденное по номеру, а тут человек уже нажал
    /// «Добавить» осознанно, из своей же карусели.
    private func addCar() {
        let tab = carTab
        let plate = carPlate
        let name = carName.trimmingCharacters(in: .whitespaces)
        let mileage = Int(carMileage.filter(\.isNumber)) ?? 0
        let photoData = newCarPhoto.flatMap { ImageLoader.encode([$0]).first }

        Task {
            let car: Car
            if tab == 0 {
                guard PlateFormat.isValid(plate),
                      let found = try? await lookup.lookup(plate: plate) else { return }
                car = Car(plate: PlateFormat.format(plate), name: found.name,
                          vin: found.displayVIN, generation: found.generation,
                          odometer: found.odometer ?? 0, photo: photoData)
            } else {
                guard !name.isEmpty else { return }
                car = Car(plate: "", name: name, odometer: mileage, photo: photoData)
            }

            // Индекс берём до вставки: это и есть номер страницы новой машины
            let newPage = cars.count
            modelContext.insert(car)
            carPage = newPage
            carPlate = ""
            carName = ""
            carMileage = ""
            newCarPhoto = nil
            carPhotoItems = []
        }
    }

    private func deleteCar() {
        guard let car else { return }
        // После удаления машин станет на одну меньше — страницу подтягиваем,
        // иначе карусель окажется за последней страницей.
        carPage = max(0, min(carPage, cars.count - 2))
        // ТО и чеки уходят каскадом — правило задано в модели Car.services
        modelContext.delete(car)
    }

    /// Форма одна на все записи, поэтому её надо чистить за собой. Фото до
    /// этого не чистились вовсе — пока они никуда не сохранялись, это было
    /// незаметно, а теперь прицепились бы к следующему ТО.
    private func clearServiceForm() {
        serviceMileage = ""
        works = [ServiceWork()]
        photos = []
        photoItems = []
    }

    /// Открывает шторку с полями, заполненными из записи.
    private func startEditing(_ record: ServiceRecord) {
        serviceDate = record.date
        serviceMileage = "\(record.mileage)"
        // Форма рассчитана минимум на одну группу полей: пустой список её ломает
        let rows = record.works.map { ServiceWork(title: $0.title, amount: "\($0.amount)") }
        works = rows.isEmpty ? [ServiceWork()] : rows

        // Чеки восстанавливаются вне главного актора: их может быть много,
        // а форма должна открыться сразу.
        photos = []
        photoItems = []
        let receipts = record.receipts
        Task { photos = await ImageLoader.decode(receipts) }

        editingRecord = record
        showAddService = true
    }

    private func saveService() {
        guard let car else { return }
        let mileage = Int(serviceMileage.filter(\.isNumber)) ?? odometer
        let items = works.compactMap { work -> ServiceWorkItem? in
            let amount = Int(work.amount.filter(\.isNumber)) ?? 0
            let title = work.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty || amount > 0 else { return nil }
            return ServiceWorkItem(title: title, amount: amount)
        }

        let receipts = ImageLoader.encode(photos)
        var savedMessage = ""

        if let record = editingRecord {
            record.date = serviceDate
            record.mileage = mileage
            record.receipts = receipts
            // Старые работы удаляем явно: подмена массива оставила бы их
            // сиротами в базе — каскад срабатывает только на удаление записи.
            record.works.forEach { modelContext.delete($0) }
            record.works = items
            savedMessage = "ТО изменено!"
        } else {
            let record = ServiceRecord(date: serviceDate, mileage: mileage,
                                       receipts: receipts)
            record.works = items
            record.car = car
            modelContext.insert(record)
            addedServiceTick += 1
            savedMessage = "ТО добавлено!"
        }
        editingRecord = nil

        // Одометр не может быть меньше пробега на последнем ТО
        car.odometer = max(car.odometer, mileage)

        showAddService = false
        clearServiceForm()

        presentToast(savedMessage)
    }
}

/// Поднимается по иерархии UIKit до ближайшего UIScrollView — того самого,
/// на котором стоит SwiftUI-прокрутка. Отдельного файла не заводим: правка
/// `project.pbxproj` вручную дороже двадцати строк.
private struct ScrollViewFinder: UIViewRepresentable {
    let onFound: (UIScrollView) -> Void

    func makeUIView(context: Context) -> UIView {
        let probe = UIView()
        probe.isUserInteractionEnabled = false
        // В makeUIView вьюха ещё не вставлена в иерархию — ищем на следующем
        // витке цикла, когда superview уже есть.
        DispatchQueue.main.async { [weak probe] in
            var next = probe?.superview
            while let view = next {
                if let scroll = view as? UIScrollView { onFound(scroll); return }
                next = view.superview
            }
        }
        return probe
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// «Increment» из Page Control — плюс одним контуром.
private struct PlusGlyph: Shape {
    var thickness: CGFloat = 1.8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let t = thickness
        path.addRoundedRect(
            in: CGRect(x: 0, y: (rect.height - t) / 2, width: rect.width, height: t),
            cornerSize: CGSize(width: t / 2, height: t / 2)
        )
        path.addRoundedRect(
            in: CGRect(x: (rect.width - t) / 2, y: 0, width: t, height: rect.height),
            cornerSize: CGSize(width: t / 2, height: t / 2)
        )
        return path
    }
}

/// Шторки и пикеры главного экрана вынесены отдельно: в одном `body`
/// компилятор не вытягивал вывод типов.
private struct CarMainChrome: ViewModifier {
    @Binding var showAddCar: Bool
    @Binding var showPhotoPicker: Bool
    @Binding var photoItems: [PhotosPickerItem]
    @Binding var carTab: Int
    @Binding var carPlate: String
    @Binding var carName: String
    @Binding var carMileage: String
    @Binding var carPhotoItems: [PhotosPickerItem]
    let carPhoto: UIImage?
    let onCarPhotoLoaded: (UIImage?) -> Void
    let onSubmitCar: () -> Void
    let onPhotosLoaded: ([UIImage]) -> Void

    func body(content: Content) -> some View {
        content
            // Figma 45974:5159 → Sheet 45974:5188: «Добавить авто» открывает шторку
            // с формой. Текущая машина при этом остаётся.
            .sheet(isPresented: $showAddCar) {
                AddCarSheet(
                    tab: $carTab,
                    plate: $carPlate,
                    name: $carName,
                    mileage: $carMileage,
                    photoItems: $carPhotoItems,
                    photo: carPhoto,
                    onClose: { showAddCar = false },
                    onSubmit: {
                        showAddCar = false
                        onSubmitCar()
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
            }
            // Свой обработчик у формы авто: общий с потоком ТО открывал
            // модалку «Добавление ТО» вместо показа фото в форме машины.
            .onChange(of: carPhotoItems) { _, items in
                guard let item = items.first else { return }
                Task { onCarPhotoLoaded(await ImageLoader.load(item)) }
            }
            // «нативная штука добавления фото» (45885:3279) — системный пикер
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, matching: .images)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    // Конкурентно и вне главного актора: последовательный цикл
                    // с UIImage(data:) вешал интерфейс на несколько секунд
                    onPhotosLoaded(await ImageLoader.load(items))
                }
            }
    }
}

#Preview {
    CarMainView()
        .environmentObject(AppState())
}
