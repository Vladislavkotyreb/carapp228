import PhotosUI
import SwiftData
import SwiftUI

/// Разделяет разряды пробелами, как в макете: «9 000 000 км».
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
    /// Положение блока фото в покое в макетном режиме: 103 (отступ страницы)
    /// + заголовок 48 + 6 + номер 28 + 24. Прокси `visualEffect` меряет рамку
    /// **после** `offset` — проверено кадром: с точкой покоя без офсета фото
    /// рисовалось растянутым на 1.21 уже в покое. В режиме своего фото блок
    /// поднят на `HeaderLayout.photoRise`, и точку покоя двигает вызывающий.
    static let restingY: CGFloat = 209

    /// Прирост масштаба на точку натяжки и потолок роста.
    static let perPoint: CGFloat = 1 / 500
    static let maxGain: CGFloat = 0.35

    static func scale(pull: CGFloat) -> CGFloat {
        1 + min(max(0, pull) * perPoint, maxGain)
    }
}

/// Геометрия шапки, от её верха (экранные координаты = эти + 103).
/// Название с номером, низ фото, точки и всё, что ниже, стоят на месте в
/// обоих режимах фото — надпись не прыгает при свайпе между машинами.
/// От режима зависят только верх и ширина блока фото: в режиме своего
/// снимка он дорастает до края экрана и уходит ПОД надпись, читаемость
/// которой держит затенение верха фото.
private enum HeaderLayout {
    /// Верх блока фото в режиме макета: заголовок 48 + 6 + номер 28 + 24.
    static let photoTop: CGFloat = 106
    /// Высота блока фото из макета: 370×245.935 на всю ширину контента.
    static let photoHeight: CGFloat = 245.935
    /// На сколько блок дорастает вверх в режиме своего фото: до самого края
    /// экрана — верхний отступ страницы 103 плюс место заголовка 106.
    static let photoRise: CGFloat = 209
    /// Низ фото — общий для обоих режимов, к нему прижат и студийный ассет.
    static let photoBottom: CGFloat = photoTop + photoHeight
    /// Пейдж-контрол: 12 под фото, как в макете.
    static let dotsTop: CGFloat = photoBottom + 12
    /// Высота шапки в потоке: точки (44) — её последний элемент.
    static let height: CGFloat = dotsTop + 44
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
    /// Какая модалка открыта. Одна на всех: их и не бывает две сразу.
    /// Раньше это были пять булевых — 32 сочетания, законных шесть.
    /// Что правят, лежит отдельно в `editingRecord`: это данные, а не окно.
    @State private var sheet: CarSheet = .closed
    @State private var carTab = 0
    @State private var carPlate = ""
    @State private var carName = ""
    @State private var carMileage = ""
    /// Цена новой машины, строкой из поля. Необязательная.
    @State private var carPrice = ""
    /// Цена, которую правят прямо на плитке. Отдельно от `carPrice`: та про
    /// форму добавления, эта — про уже существующую машину.
    @State private var priceDraft = ""
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

    /// Presentation-API требуют `Binding<Bool>`, а слот у нас один.
    ///
    /// Закрытие сбрасывает слот, **только если закрывают именно эту шторку**.
    /// Без этой проверки замена одной шторки другой ломалась бы: SwiftUI
    /// досылает `false` уходящей уже после того, как открылась следующая,
    /// и та закрывалась бы сама собой.
    private func presenting(_ kind: CarSheet) -> Binding<Bool> {
        Binding(get: { sheet == kind },
                set: { shown in
                    if shown { sheet = kind }
                    else if sheet == kind { sheet = .closed }
                })
    }

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

    /// Видимость тулбара. Отдельным объектом по той же причине, что и
    /// `TabBarState`: смещение прокрутки приходит на каждом кадре, и держать
    /// его в `@State` значит пересобирать `body` шестьдесят раз в секунду —
    /// ровно та ошибка, из-за которой экран когда-то уезжал сам.
    /// Экран хранит ссылку и не подписан; подписан только тулбар.
    /// В отличие от `tabBar`, этот объект **наблюдается**: его читает сам
    /// `body` экрана — `.toolbarVisibility` и цвет заголовка. В `@State`, как
    /// `tabBar`, он лежать не может: ссылка без подписки не перерисовывает
    /// экран, и тулбар оставался спрятанным при любой прокрутке.
    ///
    /// Прокрутку это не ломает: оба флага меняются только на переходе через
    /// порог — пару раз за жест, а не на кадре.
    @StateObject private var toolbar = ToolbarVisibility()

    /// Гасим сам распознаватель, а не `isScrollEnabled`: последним управляет
    /// SwiftUI из окружения и может перезаписать его на любом обновлении, а
    /// `body` во время свайпа пересобирается каждый кадр из-за `dragX`.
    /// Профиль отказа при этом правильный: если правку всё-таки затрут,
    /// вернётся нынешнее поведение, а не мёртвая прокрутка.
    private func setScrollEnabled(_ enabled: Bool) {
        scroll.view?.panGestureRecognizer.isEnabled = enabled
    }


    /// Тот же поставщик, что и на первом экране добавления.
    private let lookup: any VehicleLookup = VehicleLookupProvider.make()

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

    /// Высота зоны свайпа от верха экрана: отступ страницы 103 + шапка 408
    /// (48 заголовок + 6 + 28 номер + 24 + 246 фото + 12 + 44 точки) + гэп 24
    /// + карточка «ТО через» 148.
    private static let swipeZoneHeight: CGFloat = 683

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
        .bottomSheet(isPresented: presenting(.serviceChoice)) {
            AddServiceChoiceSheet(
                onClose: { sheet = .closed },
                // Замена шторки — один переход, а не «закрыть и открыть»:
                // двух присваиваний подряд больше нет, и промежуточного
                // состояния с двумя открытыми тоже.
                onPickPhoto: { sheet = .photoPicker },
                onManual: { sheet = .service }
            )
        }
        .bottomSheet(isPresented: presenting(.service)) {
            AddServiceSheet(
                title: editingRecord == nil ? "Добавление ТО" : "Изменение ТО",
                date: $serviceDate,
                mileage: $serviceMileage,
                works: $works,
                photoItems: $photoItems,
                photos: $photos,
                onClose: {
                    sheet = .closed
                    // Иначе следующее «Добавить ТО» молча перезапишет запись
                    editingRecord = nil
                    clearServiceForm()
                },
                onSave: saveService
            )
            .padding(.top, 62)
        }
        .modifier(CarMainChrome(
            showAddCar: presenting(.addCar),
            showPhotoPicker: presenting(.photoPicker),
            photoItems: $photoItems,
            carTab: $carTab,
            carPlate: $carPlate,
            carName: $carName,
            carMileage: $carMileage,
            carPrice: $carPrice,
            carPhotoItems: $carPhotoItems,
            carPhoto: newCarPhoto,
            onCarPhotoLoaded: { newCarPhoto = $0 },
            onSubmitCar: addCar,
            onPhotosLoaded: { loaded in
                photos = loaded
                if !loaded.isEmpty { applyParsedService() }
            }
        ))
        // Подложка под всеми разделами. Страница машины стала чёрной целиком
        // (макет 45867:3007), и градиента под ней больше нет: раньше отсюда
        // светился #F2F2F7 из-под контента.
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea()
        // Тёмную схему объявляет RootView — одна на всё приложение.
        // «нативная штука добавления фото» (45885:3279) — системный пикер,
        // после выбора открываем форму с уже прикреплённым файлом.
        .animation(Motion.toast(reduceMotion: reduceMotion), value: showToast)
        .onChange(of: tab) { _, new in
            // Смещения прежнего раздела к новому отношения не имеют, а бар
            // должен встречать раздел развёрнутым.
            tabBar.reset()
            toolbar.reset()
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
        // Правка цены — системный алерт с полем: ради одного числа отдельная
        // форма была бы тяжелее самого действия.
        .alert("Цена авто", isPresented: presenting(.priceEdit)) {
            TextField("Цена в рублях", text: $priceDraft)
                .keyboardType(.numberPad)
            Button("Отмена", role: .cancel) { priceDraft = "" }
            Button("Сохранить") { savePrice() }
        }
        .confirmationDialog("Удалить авто?", isPresented: presenting(.deleteConfirm), titleVisibility: .visible) {
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
            Tab("Машина", systemImage: "car", value: 0) {
                NavigationStack {
                    // С тёмной темой всего приложения схему больше никто не
                    // переопределяет: и стек, и тулбар, и содержимое живут
                    // в одной тёмной. Кнопки тулбара при этом рисуют своё
                    // тёмное стекло сами (`darkGlassCard`) и от схемы бара
                    // не зависят.
                    ZStack { carScreen }
                        // Свой фон обязателен: `NavigationStack` подкладывает
                        // непрозрачный `systemBackground`, и явный чёрный
                        // гарантирует, что ниже контента не вылезет шов.
                        .background(Color.black)
                        .ignoresSafeArea()
                        // Краевой эффект прокрутки размывал карточку «ТО через»
                        // под баром. В макете под тулбаром контент чёткий.
                        .scrollEdgeEffectHidden(true, for: .top)
                        .toolbar { carToolbar }
                        // Фон бара скрыт: в макете контент уходит под тулбар,
                        // фото машины видно за ним.
                        .toolbarBackground(.hidden, for: .navigationBar)
                        // В покое тулбара нет — он появляется при прокрутке,
                        // как показано в ноде «поведение при скролле».
                        .toolbarVisibility(toolbar.isVisible ? .visible : .hidden,
                                           for: .navigationBar)
                }
            }
            Tab("Карта", systemImage: "map", value: 1) { MapScreen() }
            Tab("Ошибки", systemImage: "wrench.adjustable", value: 2) {
                IssuesScreen(hidesTabBar: $hidesTabBar)
                    .ignoresSafeArea()
                    // Видимость бара объявляется **содержимым вкладки**, а не
                    // самим `TabView`: на `TabView` модификатор молча
                    // игнорируется, и бар оставался поверх модалки.
                    .toolbarVisibility(hidesTabBar ? .hidden : .automatic, for: .tabBar)
            }
            Tab("Ещё", systemImage: "ellipsis", value: 3) { MoreScreen().ignoresSafeArea() }
        }
        // Тёмная тема 05.09.2026: бар больше не светлый — тёмное стекло он
        // берёт из общей тёмной схемы приложения, как на тёмном рендере
        // «главная» (46225:7788). Прежний светлый вариант — в истории.
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
            case 1: MapScreen().transition(tabTransition)
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
        /// Зазор от точек до карточки. В новом макете он один и тот же в обоих
        /// состояниях — и с историей, и без неё.
        var headerGap: CGFloat = 24
        /// Натуральная высота содержимого «ТО через»: 14pt подпись (20) + 4 +
        /// значение (34) + 12 + полоса 30 плюс паддинги 48 = 148, ровно как
        /// в макете. Значение — верхняя точка смеси и порог, за которым высоту
        /// снова задаёт содержимое; насильно её не выставляем.
        var cardHeight: CGFloat = 148
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
    /// 45867:3007). Страница добавления раньше наследовала метрики последней
    /// машины, и «Добавить авто» меняла высоту: 92 после машины без ТО против
    /// 148 после машины с историей. Теперь у неё всегда крупная карточка —
    /// смешивание по весам сглаживает переход и от 92, и от 148.
    private func metrics(of page: Int) -> PageMetrics {
        guard page < cars.count else {
            return PageMetrics(headerGap: 24, cardHeight: 148, statsGap: 24, history: 0)
        }
        let index = max(0, page)
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

    /// Высота блока истории. Была константой 350: горизонтальная лента не
    /// зависела от числа записей. Вертикальный список зависит — при
    /// фиксированной высоте всё, кроме первой записи, уходило под `.clipped()`.
    ///
    /// Считается из тех же токенов, что и раскладка (нода 46165:2835):
    /// 16 отступ секции + 28 заголовок + 20 + 96 сводка, дальше на каждую
    /// группу 24 зазора + 129 (25 дата + 8 + 96 карточка), и снизу снова 16.
    /// Ошибка видна в покое щелью снизу или срезанной карточкой.
    private var historyHeight: CGFloat {
        let group: CGFloat = 129 + 24      // карточка с датой и зазор перед ней
        let n = CGFloat(services.count)
        return 176 + n * group
    }

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
                    if p > 0.5 { sheet = .addCar } else if services.isEmpty { sheet = .serviceChoice }
                } label: {
                    darkCard(progress: p, height: m.cardHeight)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(p > 0.5 ? "Добавить авто" : "ТО")

                Spacer(minLength: 0).frame(height: m.statsGap)

                // Белые карточки уходят целиком: на странице «добавить новую»
                // (нода 45949:3265) их нет вовсе, остаётся одна тёмная.
                HStack(spacing: 16) {
                    // Цена правится тапом по плитке: формы правки авто в
                    // приложении нет, а тулбар с меню есть только на iOS 26.
                    Button {
                        priceDraft = car?.price.map(String.init) ?? ""
                        sheet = .priceEdit
                    } label: {
                        statCard(title: "Цена авто") { car in
                            car.price.map { "\(NumberFormat.grouped($0))\u{00A0}₽" } ?? "—"
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Self.statCardShape)
                    .accessibilityLabel("Цена авто")
                    .accessibilityHint("Изменить")

                    statCard(title: "Пробег") { "\(NumberFormat.grouped($0.odometer))\u{00A0}км" }
                }
                .opacity(visible)
                // Погашенная плитка продолжала бы принимать касания, а на
                // странице «Добавить авто» под ней нет ничего: тап открывал бы
                // правку цены вслепую.
                .allowsHitTesting(visible > 0.5)

                // Зазор сворачивается вместе с историей, иначе у машины без ТО
                // остался бы двойной отступ до низа страницы.
                Spacer(minLength: 0).frame(height: 32 * m.history)

                historyCard()
                    .frame(height: historyHeight * m.history, alignment: .top)
                    .clipped()
                    .opacity(visible * m.history)
                    // Погашенная вьюха продолжает принимать касания —
                    // иначе «Добавить ТО» внутри неё нажимается вслепую.
                    .allowsHitTesting(visible * m.history > 0.5)

                Spacer(minLength: 0).frame(height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 103)
            .padding(.bottom, 140)
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
                // Пороги синхронизируются и здесь: при обычном входе смещение
                // нулевое и разницы нет, но появившийся уже прокрученным
                // список (восстановленная позиция) иначе встречал бы бар
                // развёрнутым, а тулбар — спрятанным.
                .onAppear {
                    scroll.offset = offset
                    tabBar.track(offset: offset)
                    toolbar.track(offset: offset)
                }
                .onChange(of: offset) { _, new in
                    scroll.offset = new
                    // Свёрнутость таббара считается здесь же и по тем же
                    // правилам, что и запрет свайпа: отдельного наблюдателя
                    // прокрутки заводить незачем.
                    tabBar.track(offset: new)
                    toolbar.track(offset: new)
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


    // MARK: - Шапка: название, номер, фото, пейдж-контрол

    /// Смесь режимов фото по страницам: 0 — студийный ассет в блоке макета,
    /// 1 — свой снимок во весь верх экрана (референс IMG_2402: фото под
    /// статус-бар, название поверх нижней кромки). Смешивается весами
    /// страниц, как остальные метрики: при свайпе между машинами с фото и
    /// без него блок перетекает, а не переключается.
    private var photoMix: Double {
        var mix = 0.0
        for car in cars where car.photo != nil {
            mix += weight(of: index(of: car))
        }
        return mix
    }

    /// `stretches` включает пружину. На экране без ТО прокрутки нет, а
    /// пространства координат `ScrollHeader.space` не существует вовсе —
    /// `frame(in:)` по неизвестному имени вернул бы мусор.
    ///
    /// Шапка собрана ZStack с офсетами, а не потоком: у неё два режима
    /// (макетный и «своё фото во весь верх»), и разница между ними — числа,
    /// которые смешивает `photoMix`. Высота в потоке постоянна, поэтому всё,
    /// что ниже шапки, не двигается ни в одном режиме.
    private func header(progress p: Double, stretches: Bool) -> some View {
        let mix = photoMix
        return ZStack(alignment: .top) {
            photoStrip(mix: mix, stretches: stretches)

            // Заголовок и номер стоят на месте в обоих режимах — надпись не
            // прыгает при свайпе; в режиме своего фото снимок уходит под неё,
            // читаемость держит затенение верха фото.
            VStack(spacing: 6) {
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
                .frame(height: 28)
            }

            pageControl
                .offset(y: HeaderLayout.dotsTop)
        }
        .frame(height: HeaderLayout.height, alignment: .top)
    }

    /// Лента фото — единственный едущий элемент карусели.
    ///
    /// Вертикаль делает `offset`, а не позиция в раскладке: layout-рамка
    /// блока стоит на месте при любом режиме, и `PhotoStretch.restingY`
    /// остаётся одной константой. Ширину в режиме своего фото добавляет
    /// отрицательный паддинг **после** клипа — так блок дорастает до краёв
    /// экрана, а обрезка идёт по уже расширенным границам.
    private func photoStrip(mix: Double, stretches: Bool) -> some View {
        // Точка покоя пружины следует за офсетом режима: прокси видит рамку
        // уже сдвинутой. Значение захватывается замыканием — оно Sendable.
        let resting = PhotoStretch.restingY - HeaderLayout.photoRise * mix
        return GeometryReader { g in
            HStack(spacing: 0) {
                ForEach(cars) { car in
                    carPhoto(for: car, width: g.size.width, height: g.size.height,
                             assetWidth: g.size.width - 32 * mix)
                }
                // Страница добавления: у неё своей машины нет
                carPhoto(for: nil, width: g.size.width, height: g.size.height,
                         assetWidth: g.size.width - 32 * mix)
            }
            .offset(x: -CGFloat(position) * g.size.width)
        }
        .frame(height: HeaderLayout.photoHeight + HeaderLayout.photoRise * mix)
        // Растворение фото в чёрный фон страницы: держит читаемость названия
        // на снимке и сшивает низ фото с экраном, как в референсе. На
        // студийных страницах гаснет вместе с mix.
        .overlay(alignment: .bottom) {
            LinearGradient(
                stops: [.init(color: .black.opacity(0), location: 0),
                        .init(color: .black.opacity(0.75), location: 0.62),
                        .init(color: .black, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 190)
            .opacity(mix)
        }
        // Затенение верха: под статус-баром и названием, которое в этом
        // режиме лежит поверх снимка. Гуще у кромки, сходит на нет к трети
        // высоты — как у системных экранов с фото под заголовком.
        .overlay(alignment: .top) {
            LinearGradient(
                stops: [.init(color: .black.opacity(0.65), location: 0),
                        .init(color: .black.opacity(0.35), location: 0.45),
                        .init(color: .black.opacity(0), location: 1)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 260)
            .opacity(mix)
        }
        .clipped()
        // Масштаб навешен ПОСЛЕ .clipped(): эффект применяется к уже
        // обрезанному результату, поэтому вторая копия фото из-под
        // клипа не вылезает.
        //
        // visualEffect, а не @State: геометрия читается на этапе
        // отрисовки и не пересобирает ScrollView — см. журнал.
        .visualEffect { content, proxy in
            let pull = stretches
                ? proxy.frame(in: .named(ScrollHeader.space)).minY - resting
                : 0
            return content.scaleEffect(PhotoStretch.scale(pull: pull), anchor: .center)
        }
        .padding(.horizontal, -16 * mix)
        .offset(y: HeaderLayout.photoTop - HeaderLayout.photoRise * mix)
    }

    /// Одно место на весь экран: то же название стоит и в шапке при прокрутке.
    /// TODO: брать из модели, когда появится справочник марок.
    private static let carTitle = "Mercedes-Benz GL-класс"

    /// Название машины. Блок в макете 370×48, текст в одну строку по центру;
    /// высота задана рамкой, а не межстрочным интервалом — у одной строки
    /// `figmaLineHeight` только сдвинул бы её вниз.
    ///
    /// Градиент не заливкой, а маской: `foregroundStyle` растягивает шкалу по
    /// **буквам**, а в макете она идёт по всей ширине блока. Разница видна
    /// замером — левый край названия выходил заметно темнее макетного.
    private func title(_ text: String) -> some View {
        Self.titleGradient
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .mask {
                Text(text)
                    .font(.system(size: 26, weight: .heavy))
                    // Трекинг снят с рендера, а не из токена: в ноде его нет
                    // вовсе, но набор там на 5pt уже нашего — Figma рисует
                    // заголовок статическим SF Pro Display, у которого
                    // межбуквенное расстояние плотнее.
                    .tracking(-0.23)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
    }

    /// Заливка названия: белый гаснет к краям до 20 % слева и 30 % справа.
    private static let titleGradient = LinearGradient(
        stops: [.init(color: .white.opacity(0.2), location: 0),
                .init(color: .white, location: 0.5),
                .init(color: .white.opacity(0.3), location: 1)],
        startPoint: .leading, endPoint: .trailing)

    /// Кадр одной страницы карусели.
    ///
    /// Свой снимок заполняет ячейку целиком с обрезкой (`scaledToFill`) — как
    /// в референсе IMG_2402, где фото уходит под статус-бар во всю ширину.
    /// Студийный ассет остаётся в ширине контента (`assetWidth`) и прижат к
    /// низу ячейки: низ фото — общая точка обоих режимов, и при смешивании
    /// ассет не ездит по вертикали, а ячейка просто дорастает вверх.
    ///
    /// Клип у каждого кадра свой, а не общий у контейнера: фото шире страницы
    /// и без этого вылезало бы на соседнюю.
    private func carPhoto(for car: Car?, width: CGFloat, height: CGFloat,
                          assetWidth: CGFloat) -> some View {
        Group {
            if let car, let image = carImages[car.persistentModelID] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
            } else {
                // Не `scaledToFill`: тот подгоняет обе стороны, и на нашем
                // широком ассете срезал машине нос и корму. Ширина явная,
                // высота за пропорцией, поля на чёрном фоне не видны.
                Image("CarPhoto")
                    .resizable()
                    .scaledToFit()
                    .frame(width: assetWidth)
                    .frame(width: width, height: height, alignment: .bottom)
            }
        }
        .frame(width: width, height: height)
        .clipped()
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
            HStack(spacing: 3.5) {
                HStack(spacing: 3.5) {
                    Text(parts[0])
                    Text(parts[1])
                    Text(parts[2])
                }

                Rectangle()
                    .fill(Figma.separatorsVibrant)
                    .frame(width: 0.875, height: 17.603)
                    .blendMode(.softLight)

                Text(parts[3])
            }
            // Узкое начертание из макета: номер набран SF Pro сжатым, поэтому
            // плашка и держится в 98pt.
            .font(Self.condensedFont(size: 14))
            .tracking(-0.4)
            .foregroundStyle(Figma.graysGray2)
            .padding(.horizontal, 10.5)
            .padding(.vertical, 3.5)
            .frame(height: 28)
            .background(Figma.fillsPrimary, in: RoundedRectangle(cornerRadius: 10.5))
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
            // Без трекинга: объявленный −0.43 до рендера не доходит, с ним
            // подпись выходила на 5pt уже макетной. Замер, не токен.
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
        // Figma 45867:2944 — «Liquid Glass - Regular - Small» в тёмном
        // варианте. Тот же рецепт, что у остальных карточек экрана.
        .darkGlassCard(in: RoundedRectangle(cornerRadius: 36))
        .motionRim(in: RoundedRectangle(cornerRadius: 36))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
    }

    private func serviceProgressContent(for car: Car) -> some View {
        VStack(spacing: 12) {
            // Те же боксы из макета: подпись 20, значение 34, между ними 4.
            // Вместе с паддингами 24 это и даёт объявленные 148 высоты.
            VStack(spacing: 4) {
                Text("ТО через")
                    .font(Self.condensedFont(size: 14))
                    .tracking(-0.4)
                    .foregroundStyle(Figma.graysGray2)
                    .frame(height: 20)

                Text("\(NumberFormat.grouped(kmUntilService(for: car)))\u{00A0}км")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(0.38)
                    .foregroundStyle(.white)
                    .frame(height: 34)
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

    /// Форма плитки счётчика. В макете её скругление — 1000, то есть капсула:
    /// на высоте 96 это ровно полукруглые торцы. Константа общая, потому что
    /// форма нужна и материалу, и его подложке — разъехавшись, они дали бы
    /// двойную кромку.
    private static let statCardShape = Capsule(style: .continuous)

    /// Подписи и номер набраны в макете узким SF Pro (ось ширины 60). Это та
    /// же ось, что у системного `.width`, поэтому шрифт берётся системный,
    /// а не отдельным файлом.
    private static func condensedFont(size: CGFloat,
                                      weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// Колонка «подпись сверху, значение снизу» высотой 47. Одна и та же и в
    /// плитках, и в сводке истории — в макете это один блок, и разъехаться
    /// их типографике нельзя.
    private func statColumn<V: View>(title: String,
                                     @ViewBuilder value: () -> V) -> some View {
        // Боксы строк заданы рамками, а не `figmaLineHeight`: у одной строки
        // тот добавляет половину интерлиньяжа сверху и уводит текст вниз,
        // а в макете это два блока фиксированной высоты — 20 и 25, между
        // ними 2. Замер показывал ровно эти 2pt расхождения.
        VStack(spacing: 2) {
            Text(title)
                .font(Self.condensedFont(size: 14))
                .tracking(-0.4)
                .foregroundStyle(Figma.vibrantSecondary)
                .frame(height: 20)

            value()
                .font(.system(size: 20, weight: .semibold))
                // Без трекинга: объявленный в ноде −0.45 до рендера не доходит,
                // и с ним значение выходило уже макетного. Проверено замером.
                .foregroundStyle(.white)
                .frame(height: 25)
        }
        .frame(height: 47)
        .frame(maxWidth: .infinity)
    }

    private func statCardShell<V: View>(title: String,
                                        @ViewBuilder value: () -> V) -> some View {
        statColumn(title: title, value: value)
            .frame(height: 96)
            .darkGlassCard(in: Self.statCardShape)
    }

    /// История обслуживания (нода 46165:2835). Белой подложки под секцией нет,
    /// но свои 16pt сверху и снизу у неё остались — горизонтальные даёт
    /// страница. Нижней кнопки «Добавить ТО» здесь нет: то же действие лежит
    /// в тулбаре, и рядом друг с другом они читались дублем.
    private func historyCard() -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                Text("История обслуживания")
                    .font(.system(size: 22, weight: .bold))
                    .figmaLineHeight(28, fontSize: 22, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)

                historySummary
            }

            historyStrip
        }
        .padding(.vertical, 16)
    }

    /// Сводка: одна карточка на две колонки. Раньше это были две плитки —
    /// макет сложил их в одну, и разделять её обратно нельзя: у колонок
    /// общая подложка и общая кромка.
    private var historySummary: some View {
        HStack(spacing: 0) {
            statColumn(title: "Количество ТО") { Text("\(services.count)") }
            statColumn(title: "Всего потрачено") { Text(totalSpent) }
        }
        .frame(height: 96)
        .darkGlassCard(in: Self.statCardShape)
    }

    // MARK: - Тулбар (нода 46165:3243)

    /// Три слота из макета: «…» слева, название по центру-слева, «Добавить ТО»
    /// справа. Системный `.toolbar`, а не своя полоса: он сам даёт безопасную
    /// зону, размытие края прокрутки, цели касания и доступность.
    @available(iOS 26.0, *)
    @ToolbarContentBuilder
    private var carToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button(role: .destructive) { sheet = .deleteConfirm } label: {
                    Label("Удалить авто", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    // Страница под баром теперь чёрная сверху донизу, поэтому
                    // и кнопки тулбара — на тёмном стекле, как карточки.
                    // Само это состояние в макете не нарисовано.
                    .darkGlassCard(in: Circle())
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("Действия с автомобилем")
        }
        // Системная подложка элемента бара гасится: она рисует своё стекло
        // ПОД нашей капсулой и над чёрной карточкой выходила тёмным кольцом
        // вокруг неё.
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .principal) {
            // 15pt Semibold, две строки, по левому краю — как в макете.
            // Ширина 167 из ноды: без неё слот жмётся к одной строке и
            // название обрезается многоточием.
            Text(car?.name ?? "")
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.23)
                .figmaLineHeight(20, fontSize: 15, weight: .semibold)
                // Белый на всей длине страницы: светлого низа, ради которого
                // цвет когда-то переключался, у неё больше нет.
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 167, alignment: .leading)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button { sheet = .serviceChoice } label: {
                Text("Добавить ТО")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 139, height: 44)
                    .darkGlassCard(in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    /// Записи ТО вертикальным списком: дата заголовком, под ней карточка.
    ///
    /// Была горизонтальная лента 230×84 — макет `45867:3007` заменил её на
    /// список во всю ширину. Вместе с лентой ушёл `shadowInset`: запас под
    /// тени и его компенсация отрицательным отступом были нужны только
    /// потому, что горизонтальный `ScrollView` обрезал тени по своим границам.
    private var historyStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(services.enumerated()), id: \.element.id) { index, record in
                if index > 0 { Spacer(minLength: 0).frame(height: 24) }

                // Дата — заголовок группы, 16pt Semibold из макета
                Text(record.date, format: .dateTime.day(.twoDigits)
                    .month(.twoDigits).year())
                    .font(.system(size: 16, weight: .semibold))
                    // Трекинга нет намеренно. В ноде он объявлен (−0.45), но
                    // до рендера не доходит: с ним дата выходила на 3pt уже
                    // макета, без него сходится в пиксель. Тот же случай, что
                    // и с заголовком, только в другую сторону, — верим замеру.
                    .foregroundStyle(.white)
                    // Бокс даты в макете 25pt. Рамкой, а не `figmaLineHeight`:
                    // тот у одной строки давал 22 и уводил каждую следующую
                    // группу на 3pt вверх — к третьей записи набегало девять.
                    .frame(height: 25)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0).frame(height: 8)

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
                        // Своё превью, а не подъём оригинала: у карточки тень
                        // нарисована за пределами её формы, и границы снимка
                        // не совпадали с ней — касание давало сжатие-отскок не
                        // по той геометрии. Размер обязан совпадать с самой
                        // карточкой, иначе возвращается та же болезнь.
                        serviceCardBody(record)
                            .frame(width: 370, height: Self.serviceCardHeight)
                            .background(Self.serviceCardShape.fill(Figma.darkCard))
                    }
            }
        }
    }

    /// Карточка записи: 370×96, `Liquid Glass - Regular - Small` из макета.
    private static let serviceCardHeight: CGFloat = 96
    private static let serviceCardShape = RoundedRectangle(cornerRadius: 34,
                                                           style: .continuous)

    private func serviceCard(_ record: ServiceRecord) -> some View {
        serviceCardBody(record)
            .frame(maxWidth: .infinity)
            .frame(height: Self.serviceCardHeight)
            .darkGlassCard(in: Self.serviceCardShape)
            // Тени из прежнего макета здесь больше нет: на чёрном фоне её
            // не видно, а кромку и объём даёт само стекло.
            .contentShape(Self.serviceCardShape)
    }

    /// Содержимое карточки без подложки: одно и то же рисуют список и превью
    /// контекстного меню, поэтому оно вынесено.
    ///
    /// Состав сменился вместе с раскладкой: было «дата · пробег · сумма», в
    /// макете — сумма сверху и перечисление работ под ней. Дата уехала в
    /// заголовок группы.
    private func serviceCardBody(_ record: ServiceRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(NumberFormat.grouped(record.amount))\u{00A0}₽")
                .font(.system(size: 15, weight: .semibold))
                // Трекинг снят по той же причине, что у даты и значений плиток.
                .foregroundStyle(.white)
                .frame(height: 20)

            // Две строки по 18 — так работы и стоят в макете; у записи с одной
            // работой строка остаётся сверху, а карточка держит свои 96.
            Text(record.works.map(\.title).joined(separator: ", "))
                .font(.system(size: 13))
                .tracking(-0.08)
                .figmaLineHeight(18, fontSize: 13)
                .foregroundStyle(Figma.vibrantSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 36, alignment: .top)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // Арифметика обслуживания живёт в `ServiceMath` и проверяется без
    // приложения (`tools/run-pure-checks.sh`). Здесь остаются переходники:
    // они достают из модели SwiftData значения и больше ничего не решают.

    private var totalSpent: String {
        "\(NumberFormat.grouped(ServiceMath.totalSpent(amounts: services.map(\.amount))))\u{00A0}₽"
    }

    /// «ТО через N км» — остаток до следующего сервиса.
    private func kmUntilService(for car: Car) -> Int {
        ServiceMath.kmUntilService(odometer: car.odometer,
                                   serviceMileages: car.services.map(\.mileage))
    }

    /// Прогресс интервала: сколько из 10 000 км уже проехали.
    private func serviceProgress(for car: Car) -> Double {
        ServiceMath.progress(odometer: car.odometer,
                             serviceMileages: car.services.map(\.mileage))
    }

    /// Разбор фото/PDF: скрипт достаёт базовые показатели и форма открывается
    /// уже заполненной — ручной ввод с нуля здесь неуместен.
    /// TODO: заменить заглушку на реальный парсер.
    private func applyParsedService() {
        serviceDate = Date()
        serviceMileage = "\(odometer)"
        works = [ServiceWork(title: "Замена масла", amount: "12000")]
        sheet = .service
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
        let mileage = NumberFormat.digits(carMileage, or: 0)
        let price = NumberFormat.digits(carPrice)
        let photoData = newCarPhoto.flatMap { ImageLoader.encode([$0]).first }

        Task {
            let car: Car
            if tab == 0 {
                guard PlateFormat.isValid(plate),
                      let found = try? await lookup.lookup(plate: plate) else { return }
                car = Car(plate: PlateFormat.format(plate), name: found.name,
                          vin: found.displayVIN, generation: found.generation,
                          odometer: found.odometer ?? 0, price: price, photo: photoData)
            } else {
                guard !name.isEmpty else { return }
                car = Car(plate: "", name: name, odometer: mileage,
                          price: price, photo: photoData)
            }

            // Индекс берём до вставки: это и есть номер страницы новой машины
            let newPage = cars.count
            modelContext.insert(car)
            carPage = newPage
            carPlate = ""
            carName = ""
            carMileage = ""
            carPrice = ""
            newCarPhoto = nil
            carPhotoItems = []
        }
    }

    /// Пустое поле стирает цену: у машины её может не быть вовсе, и пустая
    /// честнее оставленной от прошлого ввода.
    private func savePrice() {
        car?.price = NumberFormat.digits(priceDraft)
        priceDraft = ""
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
        sheet = .service
    }

    private func saveService() {
        guard let car else { return }
        let mileage = NumberFormat.digits(serviceMileage, or: odometer)
        let items = works.compactMap { work -> ServiceWorkItem? in
            let amount = NumberFormat.digits(work.amount, or: 0)
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
        car.odometer = ServiceMath.odometerAfterService(current: car.odometer,
                                                        serviceMileage: mileage)

        sheet = .closed
        clearServiceForm()

        presentToast(savedMessage)
    }
}

/// Поднимается по иерархии UIKit до ближайшего UIScrollView — того самого,
/// на котором стоит SwiftUI-прокрутка. Отдельного файла не заводим: правка
/// `project.pbxproj` вручную дороже двадцати строк.
private extension View {
    /// Тёмное стекло карточек главной: «Liquid Glass - Regular - Small» в
    /// тёмном варианте. Один рецепт на все карточки экрана — они и в макете
    /// один компонент.
    ///
    /// Рисуем сами (`kind: .painted`), потому что `glassEffect` не отдаёт
    /// наружу ни толщину кромки, ни внутренние тени. Профиль снят колонкой
    /// пикселей с рендера и одинаков у всех карточек: заливка #1A1A1A, сверху
    /// затемнение до 18/255, сходящее на нет к 28pt, снизу подсветка до 30 и
    /// волосяная кромка по контуру.
    func darkGlassCard<S: Shape>(in shape: S) -> some View {
        liquidGlass(in: shape, tint: Figma.darkCard, kind: .painted) {
            shape.fill(Figma.darkCard)
                .overlay {
                    // Полосы в точках, а не в долях высоты: в макете это
                    // внутренние тени с абсолютным радиусом, и у карточки
                    // 246pt они такие же, как у плитки 96pt.
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(0.31), .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 28)

                        Spacer(minLength: 0)

                        LinearGradient(colors: [.clear, .white.opacity(0.02)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 12)
                    }
                    .clipShape(shape)
                }
                // Кромка. В макете она объявлена обводкой 0.5pt цветом
                // #A6A6A6, но обводка там внутренняя, а `stroke` кладёт линию
                // по центру контура — тем же цветом край выходил вдвое ярче
                // рендера (107 против 65 суммарно по двум строкам). Значение
                // подобрано замером, а не переписано из ноды.
                .overlay(shape.stroke(Color(white: 0.4), lineWidth: 0.5))
        }
    }
}

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
    @Binding var carPrice: String
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
                    price: $carPrice,
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
