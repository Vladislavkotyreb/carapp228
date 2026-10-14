import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Разделяет разряды пробелами, как в макете: «9 000 000 км».
/// Константы шапки при прокрутке. Вынесены из вью намеренно: замыкание
/// `visualEffect` помечено `@Sendable` и не может читать статики, изолированные
/// главным актором.
private enum ScrollHeader {
    static let space = "carScroll"
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
    /// «Записаться» нажали: карта, открывшись, найдёт ближайший сервис и
    /// сбросит флаг. См. `MapScreen.findsNearestService`.
    @State private var findsNearestService = false
    @State private var carPage = 0
    /// Выезд машины при входе в приложение: блок фото выкатывается слева и
    /// плавно тормозит. Играет один раз за жизнь экрана — guard в onAppear
    /// не даёт повториться при возвратах на вкладку «Машина».
    @State private var carDriveIn = false
    @State private var dragX: CGFloat = 0
    /// Ось жеста фиксируется на первом заметном смещении и держится до конца.
    /// Раньше решение принималось на каждом кадре — отсюда дёрганье.
    @State private var swipeAxis: SwipeAxis?
    /// Какая модалка открыта. Одна на всех: их и не бывает две сразу.
    /// Раньше это были пять булевых — 32 сочетания, законных шесть.
    /// Что правят, лежит отдельно в `editingRecord`: это данные, а не окно.
    @State private var sheet: CarSheet = .closed
    @State private var carTab = VehicleLookupProvider.isAvailable ? 0 : 1
    @State private var carPlate = ""
    @State private var carName = ""
    @State private var carMileage = ""
    /// Цена новой машины, строкой из поля. Необязательная.
    @State private var carPrice = ""
    /// Цена, которую правят прямо на плитке. Отдельно от `carPrice`: та про
    /// форму добавления, эта — про уже существующую машину.
    /// Свой пикер у формы авто. Раньше она писала в общий photoItems, который
    /// слушает поток ТО, — выбор фото открывал чужую модалку и терялся.
    @State private var carPhotoItems: [PhotosPickerItem] = []
    @State private var newCarPhoto: UIImage?
    /// Раскодированный снимок текущей машины. Держим готовым: `body`
    /// пересобирается на каждом кадре свайпа, декодировать в нём нельзя.
    /// Раскодированные снимки машин. Держим готовыми: `body` пересобирается
    /// на каждом кадре свайпа, декодировать в нём нельзя.
    @State private var carImages: [PersistentIdentifier: UIImage] = [:]
    /// Студийные кадры каталога для машин без своего фото — подбор по
    /// названию через `CarCatalog`, файлы в `Resources/CarCatalog/`.
    @State private var catalogImages: [PersistentIdentifier: UIImage] = [:]
    @State private var showToast = false
    /// Вид тоста: успех гаснет сам, процесс висит до смены, ошибка держится
    /// дольше — её читают, а не узнают по галочке.
    private enum ToastKind { case success, progress, error }
    @State private var toastKind: ToastKind = .success
    /// Найденная по номеру машина — данные для шторки «Это ваш автомобиль?».
    @State private var foundCar: FoundCar?
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
    /// Прослушивания текущей машины, свежие сверху.
    private var checks: [EngineCheck] { (car?.checks ?? []).sorted { $0.date > $1.date } }

    /// Итог быстрого прослушивания: живёт между шторкой записи и шторкой
    /// находок. Отдельно от слота `sheet`: это данные, а не «какое окно
    /// открыто» — то же разделение, что у `editingRecord`.
    @State private var quickOutcome: DiagnosisCards.Outcome?
    /// Прослушивание из ленты истории, открытое шторкой. Значения, а не
    /// модель, и отдельно от слота `sheet` — как `editingRecord`.
    @State private var viewingCheck: SavedCheck?

    /// Фильтр общей ленты «История обслуживания» (вариант B).
    @State private var historyFilter: HistoryFilter = .all

    /// Поездка из ленты «Поездки», с которой сейчас работают: открыта
    /// экраном, удаляется или правится. Значения, а не модель, и отдельно от
    /// слота `sheet` — как `viewingCheck`.
    @State private var viewingTrip: TripDetails?
    /// Поле правки расстояния поездки, км.
    @State private var tripKm = ""

    /// Поездки этой машины, свежие сверху, — под чипсом «Поездки».
    private var carTrips: [Trip] {
        (car?.trips ?? []).sorted { $0.endedAt > $1.endedAt }
    }
    /// То, что лента показывает: значения, снятые с поездок.
    private var shownTrips: [TripDetails] {
        carTrips.prefix(Self.tripsShown).map { TripDetails($0) }
    }
    /// Сколько поездок показывать: лента не ленивая, и у каждой карточки
    /// кадр карты.
    private static let tripsShown = 10

    /// Лента: ТО и прослушивания одной хронологией, свежие сверху.
    private var historyItems: [HistoryItem] {
        let items: [HistoryItem] = switch historyFilter {
        // «Всё» — это всё: ТО, прослушивания и поездки одной хронологией
        // (замечание пользователя 09.10.2026: «не выводятся поездки»).
        // Поездки здесь — строками той же высоты, что остальные записи;
        // карточки с картой — под чипсом «Поездки».
        case .all: services.map(HistoryItem.service) + checks.map(HistoryItem.check)
            + carTrips.prefix(Self.tripsShown).map(HistoryItem.trip)
        case .services: services.map(HistoryItem.service)
        case .checks: checks.map(HistoryItem.check)
        // У поездок своя лента — `tripsStrip`.
        case .trips: []
        }
        return items.sorted { $0.date > $1.date }
    }
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
                onPickPhoto: { sheet = .docSource },
                onManual: { sheet = .service }
            )
        }
        // «Что расскажем сервису» (вариант D): сводка перед картой. Кнопки
        // шторки закрывают её и ведут дальше — на карту или в «Ошибки».
        .bottomSheet(isPresented: presenting(.booking)) {
            if let car {
                BookingSummarySheet(
                    model: bookingModel(for: car),
                    onClose: { sheet = .closed },
                    onFindService: {
                        sheet = .closed
                        findsNearestService = true
                        tab = 1
                    },
                    onListen: { sheet = .listening }
                )
                // Состояние шторки (приложить ли прослушивание) задаётся при
                // создании, а вью живёт между показами: без `id` переключатель
                // помнил «выключено» с открытия, когда прослушивания ещё не было
                // (кадр 26.09). Новое прослушивание или другая машина — новая шторка.
                .id("\(car.persistentModelID.hashValue)-\(car.lastCheck?.date.timeIntervalSince1970 ?? 0)")
            }
        }
        // Быстрое прослушивание — та же модалка записи, что в «Ошибках»
        // (затемнение, панель 370×549, рост из кнопки, хаптик), затем
        // стандартная «Вот что мы нашли». Замена одной модалки другой — один
        // переход слота, как у остальных пар.
        .overlay {
            QuickListenOverlay(isPresented: sheet == .listening) { outcome in
                quickOutcome = outcome
                sheet = .findings
            }
        }
        .bottomSheet(isPresented: presenting(.checkDetail),
                     grabberInset: SavedCheckSheet.topInset) {
            if let viewingCheck {
                SavedCheckSheet(check: viewingCheck, onClose: { sheet = .closed })
                    .id(viewingCheck.id)
                    .padding(.top, SavedCheckSheet.topInset)
            }
        }
        .bottomSheet(isPresented: presenting(.findings)) {
            if let outcome = quickOutcome {
                // Слушали с экрана машины — прикрепление включено и стоит на
                // ней; в карусели можно перелистнуть на другую или выключить.
                FindingsSheet(
                    findings: outcome.cards,
                    empty: outcome.empty,
                    cars: cars.map(FindingsSheet.CarChoice.init),
                    preselected: car?.persistentModelID,
                    attachByDefault: true,
                    onClose: { sheet = .closed },
                    onApprove: { carID in
                        let target = cars.first { $0.persistentModelID == carID }
                        EngineCheck.record(outcome.cards, car: target, in: modelContext)
                        sheet = .closed
                        presentToast("Прослушивание сохранено")
                        addedServiceTick += 1
                    },
                    onRetry: { sheet = .listening }
                )
            }
        }
        // Шторка цены (референс пользователя): крупная цена, объяснение
        // средней по рынку, карандаш ведёт в алерт правки — замена шторки
        // алертом идёт через тот же слот, как и у остальных пар.
        .bottomSheet(isPresented: presenting(.priceInfo)) {
            PriceInfoSheet(
                ownPrice: car?.price,
                marketPrice: car?.marketPrice,
                marketOffers: car?.marketOffers,
                // Правка теперь в самой шторке (нода 46261:4222) — системный
                // алерт с полем упразднён макетом. Пустое поле стирает цену.
                // Сохранение закрывает шторку и отчитывается тостом с
                // хаптиком — просьба пользователя: раньше значение молча
                // уезжало, а шторка оставалась открытой.
                onSave: { value in
                    car?.price = value
                    sheet = .closed
                    presentToast(value == nil ? "Цена очищена" : "Цена обновлена!")
                    addedServiceTick += 1
                },
                onResetToMarket: {
                    car?.price = nil
                    sheet = .closed
                    presentToast("Вернули рыночную цену")
                    addedServiceTick += 1
                },
                onClose: { sheet = .closed }
            )
        }
        .bottomSheet(isPresented: presenting(.odometerInfo)) {
            PriceInfoSheet(
                kind: .odometer,
                odometer: car?.odometer ?? 0,
                trackedKm: car?.trackedKm ?? 0,
                serviceMileages: car?.services.map(\.mileage) ?? [],
                ownPrice: car?.price,
                marketPrice: car?.marketPrice,
                marketOffers: car?.marketOffers,
                onSave: { value in
                    car?.odometer = value ?? 0
                    // Пробег сверен с приборкой: поездки автопробега в нём
                    // больше не оценка, «≈» снимается.
                    car?.trackedKm = nil
                    car?.tripCarry = nil
                    sheet = .closed
                    presentToast("Пробег обновлён!")
                    addedServiceTick += 1
                },
                onClose: { sheet = .closed }
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
        // «Это ваш автомобиль?» — тот же шаг и та же шторка (45854:2936),
        // что на первом входе: находка по номеру требует подтверждения,
        // а не молча становится машиной.
        .bottomSheet(isPresented: presenting(.carFound)) {
            if let foundCar {
                CarFoundSheet(
                    car: foundCar,
                    onClose: {
                        sheet = .closed
                        self.foundCar = nil
                    },
                    onConfirm: confirmFoundCar,
                    // Поля формы целы — человек возвращается и правит номер;
                    // тост не нужен, системная шторка всё равно его накроет.
                    onReject: {
                        self.foundCar = nil
                        sheet = .addCar
                    }
                )
                .padding(.bottom, 5.07)
            }
        }
        .modifier(TripModals(
            trip: viewingTrip,
            showDetail: presenting(.tripDetail),
            showDelete: presenting(.tripDelete),
            showDistance: presenting(.tripDistance),
            km: $tripKm,
            onDelete: removeViewedTrip,
            onSaveDistance: saveTripDistance,
            onClose: { sheet = .closed }
        ))
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
                guard let first = loaded.first else { return }
                Task {
                    let parsed = await ServiceDocScanner.parse(image: first)
                    guard !Task.isCancelled else { return }
                    applyParsedService(parsed)
                }
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
        // Панель «Скрыть/Готово» над клавиатурой: цифровую иначе не закрыть.
        // Один общий предок покрывает и шторки-оверлеи (форма ТО, цена).
        .keyboardDismissBar()
        // Декодирование вне главного актора, как и у чеков ТО
        .task(id: carPhotoKey) {
            var decoded: [PersistentIdentifier: UIImage] = [:]
            var catalog: [PersistentIdentifier: UIImage] = [:]
            for car in cars {
                if let data = car.photo {
                    if let image = await ImageLoader.decode([data]).first {
                        decoded[car.persistentModelID] = image
                    }
                } else if let slug = CarCatalog.slug(name: car.name,
                                                     generation: car.generation,
                                                     plate: car.plate),
                          let url = Bundle.main.url(forResource: slug,
                                                    withExtension: "heic",
                                                    subdirectory: "CarCatalog"),
                          let image = UIImage(contentsOfFile: url.path) {
                    catalog[car.persistentModelID] = image
                }
            }
            carImages = decoded
            catalogImages = catalog
        }
        // Напоминание о ТО: пересчитывается при смене пробега и истории.
        // Ключ включает и то, и другое — иначе после сохранения ТО
        // уведомление осталось бы от прошлого расчёта.
        .task(id: serviceReminderKey) {
            for car in cars {
                await ServiceReminder.update(
                    id: ServiceReminder.key(createdAt: car.createdAt),
                    name: car.name, plate: car.plate,
                    kmLeft: kmUntilService(for: car))
            }
        }
        // Рыночная цена: раз в неделю на машину, только по полному VIN.
        .task(id: marketPriceKey) {
            guard MarketValuation.isConfigured else { return }
            for car in cars {
                guard MarketPrice.canEstimate(vin: car.vin),
                      MarketPrice.needsRefresh(updatedAt: car.marketPriceDate, now: .now),
                      let vin = car.vin else { continue }
                do {
                    let estimate = try await MarketValuation.estimate(vin: vin)
                    car.marketPrice = estimate.average
                    car.marketOffers = estimate.offers
                    car.marketPriceDate = .now
                } catch VehicleLookupError.notFound {
                    // Данных по модели нет — не переспрашивать неделю: ответ
                    // не изменится, а запросы платные. Дата без цены ровно
                    // это и значит.
                    car.marketPriceDate = .now
                } catch {
                    // Сеть или сервис: попробуем при следующем входе на экран.
                }
            }
        }
        // Отклик при смене машины: мягкий удар, а не сухой щелчок пикера —
        // перелистывание карточки ощущается «мясистее». Срабатывает на
        // защёлкивании страницы, а не по ходу пальца: незасчитанный свайп
        // не меняет carPage и потому молчит.
        .sensoryFeedback(.impact(flexibility: .soft), trigger: carPage)
        // Подтверждение удаления машины — по эталону пользователя (флоу
        // удаления фото в системной «Фото»): центрированная карточка на
        // материале, объяснение последствий, одно красное действие; тап
        // мимо — отмена. Системный confirmationDialog заменён.
        .overlay {
            if sheet == .deleteConfirm {
                deleteConfirmModal
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .animation(Motion.toast(reduceMotion: reduceMotion),
                   value: sheet == .deleteConfirm)
        // «Добавить фото или PDF»: галерея отдаёт только снимки, PDF живёт
        // в «Файлах» — источник выбирается системным диалогом.
        .confirmationDialog("Откуда взять бланк?", isPresented: presenting(.docSource),
                            titleVisibility: .visible) {
            Button("Из галереи") { sheet = .photoPicker }
            Button("Файл PDF или скан") { sheet = .filePicker }
            Button("Отмена", role: .cancel) {}
        }
        .fileImporter(isPresented: presenting(.filePicker),
                      allowedContentTypes: [.pdf, .image]) { result in
            if case .success(let url) = result { importServiceDocument(url) }
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
                        // Подложка бара с тенью — HIG-отделение шапки от
                        // контента, когда он уходит под неё. Прозрачностью,
                        // а не условием: слой должен растворяться.
                        .overlay(alignment: .top) { toolbarBackdrop }
                        // Оверлей после `ignoresSafeArea`: сам он безопасную
                        // зону уважает и встаёт над таббаром.
                        .overlay(alignment: .bottom) { bookingPill }
                        .toolbar { carToolbar }
                        // Фон бара скрыт: в макете контент уходит под тулбар,
                        // фото машины видно за ним.
                        .toolbarBackground(.hidden, for: .navigationBar)
                        // Бар существует всегда, прячется только содержимое
                        // (прозрачностью в carToolbar). Переключение
                        // .visible/.hidden меняло инсеты UIScrollView без
                        // анимации — позиция прокрутки «возвращалась сменой
                        // кадра», это и был баг из отзыва пользователя.
                        .toolbarVisibility(.visible, for: .navigationBar)
                }
            }
            Tab("Карта", systemImage: "map", value: 1) { MapScreen(findsNearestService: $findsNearestService) }
            Tab("Диагностика", systemImage: "wrench.adjustable", value: 2) {
                IssuesScreen(hidesTabBar: $hidesTabBar, car: car)
                    .ignoresSafeArea()
                    // Видимость бара объявляется **содержимым вкладки**, а не
                    // самим `TabView`: на `TabView` модификатор молча
                    // игнорируется, и бар оставался поверх модалки.
                    .toolbarVisibility(hidesTabBar ? .hidden : .automatic, for: .tabBar)
            }
            Tab("Ещё", systemImage: "ellipsis", value: 3) { MoreScreen() }
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
            case 1: MapScreen(findsNearestService: $findsNearestService).transition(tabTransition)
            case 2: IssuesScreen(hidesTabBar: $hidesTabBar, car: car)
                    .ignoresSafeArea().transition(tabTransition)
            case 3: MoreScreen().transition(tabTransition)
            default: carScreen.transition(tabTransition)
            }

            if tab == 0 {
                bookingPill
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, Figma.tabBarHeight + Figma.minBottomGap)
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

            ZStack {
                carPageBody(progress: p)
                    // simultaneousGesture, а не gesture: заполненная страница —
                    // вертикальный ScrollView, и он забирал свайп себе, поэтому
                    // над картинкой машины и карточкой ТО карусель не листалась.
                    .simultaneousGesture(carouselDrag(width: width))

                // Источник света у левого края — глубина чёрного экрана.
                // Поверх контента аддитивно, а не подложкой: под непрозрачной
                // ячейкой фото подложка не светит, и блок выдавал себя
                // резкой границей. Неподвижен при прокрутке: свет принадлежит
                // сцене, а не контенту. Просьба пользователя, в макете его нет.
                RadialGradient(colors: [Color.white.opacity(0.09), .clear],
                               center: UnitPoint(x: -0.25, y: 0.34),
                               startRadius: 0, endRadius: 480)
                    // Обычная альфа, не plusLighter: режим смешивания
                    // заставлял перекомпозичивать весь экран каждый кадр.
                    .allowsHitTesting(false)
            }
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
            // Тёмная редакция (нода 46225:7674): карточка «Добавить авто» —
            // 370×92, всегда. Прежние «всегда 148» отменены макетом; на
            // непостоянную высоту в смеси и жаловался пользователь.
            return PageMetrics(headerGap: 24, cardHeight: 92, statsGap: 24, history: 0)
        }
        let index = max(0, page)
        guard cars.indices.contains(index) else { return PageMetrics() }
        let car = cars[index]
        if car.services.isEmpty {
            // ТО ещё нет — карточка «Добавить ТО». История при этом может
            // быть: прослушивания и поездки. Раньше блок прятался целиком, и
            // у машины без ТО поездок не было видно вовсе (разбор 09.10.2026).
            return PageMetrics(headerGap: 24, cardHeight: 92, statsGap: 24,
                               history: Self.hasHistory(car) ? 1 : 0)
        }
        // Кнопка «Записаться» растит карточку на свою высоту и зазор до
        // полосы — смесь по весам делает это плавно и при свайпе.
        return suggestsBooking(car)
            ? PageMetrics(cardHeight: PageMetrics().cardHeight + Self.bookingRowHeight)
            : PageMetrics()
    }

    /// Есть ли у машины что показать в «Истории обслуживания».
    private static func hasHistory(_ car: Car) -> Bool {
        !car.services.isEmpty || !car.checks.isEmpty || !car.trips.isEmpty
    }

    /// Сколько записей в истории текущей машины. Удаляют последнюю —
    /// страницу сначала возвращают наверх (см. `deleteService`).
    private var historyCount: Int {
        services.count + checks.count + (car?.trips.count ?? 0)
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
    ///
    /// С лентой ТО и прослушиваний (вариант B) к сумме добавилась строка
    /// фильтра: 32 капсулы + 24 зазора. Группы считаются по отфильтрованной
    /// ленте — прослушивание той же высоты, что и ТО.
    private var historyHeight: CGFloat {
        guard historyFilter != .trips else {
            return 176 + Self.historyFilterRow + tripsHeight
        }
        let group: CGFloat = 129 + 24      // карточка с датой и зазор перед ней
        let n = CGFloat(historyItems.count)
        return 176 + Self.historyFilterRow + n * group
    }

    /// Высота ленты поездок вместе с зазором перед ней. У поездки с маршрутом
    /// карточка выше на карту, поэтому сумма, а не число на множитель.
    private var tripsHeight: CGFloat {
        let shown = shownTrips
        guard !shown.isEmpty else { return Self.historyGap + Self.tripsEmptyHeight }
        let cards = shown.reduce(CGFloat(0)) { $0 + TripCard.height(hasMap: $1.hasMap) }
        return Self.historyGap + cards + Self.tripGap * CGFloat(shown.count - 1)
    }

    /// Зазор между строкой чипсов и лентой — тот же, что между группами.
    private static let historyGap: CGFloat = 24
    private static let tripGap: CGFloat = 12
    /// Строка «Поездок пока нет».
    private static let tripsEmptyHeight: CGFloat = 20

    private static let historyFilterRow: CGFloat = 32 + 24

    private func carPageBody(progress p: Double) -> some View {
        let visible = 1 - p
        let m = blended

        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header(stretches: true)

                Spacer(minLength: 0).frame(height: m.headerGap)

                // На второй странице карточка превращается в кнопку
                // добавления авто; на машине это сводка или «Добавить ТО».
                Button {
                    if p > 0.5 { sheet = .addCar } else if services.isEmpty { sheet = .serviceChoice }
                } label: {
                    darkCard(height: m.cardHeight)
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
                        sheet = .priceInfo
                    } label: {
                        // Своя цена главнее рыночной: пользователь вводил её
                        // сознательно. Рыночная — с «≈»: это средняя по
                        // объявлениям, а не цена этой машины.
                        statCard(title: "Цена авто") { car in
                            if let price = car.price {
                                "\(NumberFormat.grouped(price))\u{00A0}₽"
                            } else if let market = car.marketPrice {
                                "≈\u{00A0}\(NumberFormat.grouped(market))\u{00A0}₽"
                            } else {
                                "—"
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Self.statCardShape)
                    .accessibilityLabel("Цена авто")
                    .accessibilityHint("Подробнее и изменить")

                    // Пробег правится той же шторкой, что и цена
                    // (просьба пользователя): подача и ввод одинаковые.
                    Button {
                        sheet = .odometerInfo
                    } label: {
                        statCard(title: "Пробег") {
                            TripMath.odometerLabel($0.odometer, trackedKm: $0.trackedKm ?? 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Self.statCardShape)
                    .accessibilityLabel("Пробег")
                    .accessibilityHint("Изменить")
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
        // занимают, а у машины без истории прокручивать нечего — в обоих
        // случаях прокрутка открывала бы пустоту. Флаг считается из carPage и
        // dragX, залипнуть не может.
        .scrollDisabled(p > 0.5 || historyCount == 0)
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
    private func header(stretches: Bool) -> some View {
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
                    title("Добавьте новое авто").opacity(weight(of: addPageIndex))
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
        // Выезд машины на первом кадре — первая версия по выбору пользователя:
        // пружинный докат с лёгким клевком при остановке. Едет только блок
        // фото — подписи и карточки стоят. Два случая играют проявлением
        // вместо движения: Reduce Motion (HIG) и режим своего снимка —
        // у реального фото видны края кадра, и слайд читался бы как летящий
        // прямоугольник, а не как машина.
        .offset(x: carDriveIn || !slides ? 0 : -440)
        .rotationEffect(.degrees(carDriveIn || !slides ? 0 : -1.6), anchor: .bottom)
        .opacity(carDriveIn || slides ? 1 : 0)
        .onAppear {
            guard !carDriveIn else { return }
            let animation: Animation = slides
                ? .interpolatingSpring(stiffness: 110, damping: 15).delay(0.5)
                : .easeOut(duration: 0.5).delay(0.3)
            withAnimation(animation) { carDriveIn = true }
        }
    }

    /// Выезд уместен только у студийного кадра на чёрном фоне.
    private var slides: Bool { !reduceMotion && photoMix < 0.5 }

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

    /// Заливка названия — общий токен `Figma.titleGradient`: той же
    /// заливкой набраны крупные заголовки остальных экранов.
    private static let titleGradient = Figma.titleGradient

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
            } else if let car, let image = catalogImages[car.persistentModelID] {
                // Кадр каталога — той же природы, что общий ассет (студийный
                // на чёрном), и рендерится тем же режимом, а не scaledToFill.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: assetWidth)
                    .frame(width: width, height: height, alignment: .bottom)
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

    /// Ключ пересчёта напоминаний: пробеги машин и число записей ТО.
    private var serviceReminderKey: String {
        cars.map { "\($0.persistentModelID.hashValue)-\($0.odometer)-\($0.services.count)" }
            .joined(separator: "|")
    }

    /// Ключ обновления рыночных цен: состав машин и их VIN. Даты последнего
    /// обновления в ключе нет намеренно: запись свежей даты из самой задачи
    /// не должна перезапускать задачу.
    private var marketPriceKey: String {
        cars.map { "\($0.persistentModelID.hashValue)-\($0.vin ?? "")" }
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
        // Скраб по индикатору, как у системного Page Control
        // (allowsContinuousInteraction): палец едет по капсуле — страницы
        // листаются под ним. Хаптик даёт существующий sensoryFeedback на
        // carPage. GeometryReader именно в overlay капсулы: снаружи frame
        // растягивает область на весь экран, и координаты бы врали.
        .overlay {
            GeometryReader { g in
                Color.clear
                    .contentShape(Capsule())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // Во время ведения — короткая жёсткая
                                // анимация: полная пружина Motion.page на
                                // каждый пиксель наслаивалась, заголовки
                                // мешались, а страница застревала между
                                // машинами.
                                guard let page = scrubPage(
                                    x: value.location.x, width: g.size.width),
                                      page != carPage else { return }
                                withAnimation(.easeOut(duration: 0.12)) {
                                    carPage = page
                                }
                            }
                            .onEnded { value in
                                // Дожим: что бы ни осталось от быстрых шагов,
                                // конечное положение — ровно одна страница.
                                let page = scrubPage(
                                    x: value.location.x, width: g.size.width)
                                withAnimation(Motion.page) {
                                    carPage = page ?? carPage
                                    dragX = 0
                                }
                            }
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }

    /// Страница под пальцем при скрабе по индикатору; nil — мимо капсулы.
    private func scrubPage(x: CGFloat, width: CGFloat) -> Int? {
        guard width > 0 else { return nil }
        let pages = cars.count + 1
        let raw = Int(x / width * CGFloat(pages))
        return min(pages - 1, max(0, raw))
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
    private func darkCard(height: CGFloat) -> some View {
        ZStack {
            // В раскладку попадают только видимые страницы. ZStack меряется по
            // самому высокому ребёнку, погашенному в ноль тоже: с появлением
            // строки «Записаться» карточка машины без неё (зелёная зона)
            // вырастала в покое до высоты чужой, красной (замечание
            // пользователя 26.09.2026). В покое видна одна страница — высоту
            // задаёт её содержимое; в свайпе — две соседние, как и было.
            ForEach(cars) { car in
                let w = weight(of: index(of: car))
                if w > 0 {
                    Group {
                        if car.services.isEmpty {
                            addLabel("Добавить ТО")
                        } else {
                            serviceProgressContent(for: car)
                        }
                    }
                    .opacity(w)
                }
            }

            if weight(of: addPageIndex) > 0 {
                addLabel("Добавить авто").opacity(weight(of: addPageIndex))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        // Когда история на месте целиком, высоту задаёт содержимое — так
        // карточка в покое остаётся ровно такой, какой была. Смешанное
        // значение включается только в движении, где важна плавность,
        // а не попадание в пиксель.
        .frame(height: height >= max(PageMetrics().cardHeight, settledCardHeight) - 0.5
                   ? nil : height)
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
                    // Светофор: число красное, когда ехать пора прямо
                    // сейчас, — иначе цвет полосы легко пропустить.
                    .foregroundStyle(ServiceMath.urgency(kmLeft: kmUntilService(for: car))
                                     == .urgent ? Figma.accentsRed : .white)
                    .contentTransition(.numericText())
                    .frame(height: 34)
            }
            .frame(maxWidth: .infinity)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Figma.trackBackground)

                    // Ширина не опускается ниже высоты полосы: с
                    // `RoundedRectangle(24)` малый прогресс вырождался в
                    // кривой огрызок, а сразу после ТО полоса пропадала
                    // вовсе. И меняется она анимацией, а не скачком.
                    Capsule()
                        .fill(urgencyColor(for: car))
                        .frame(width: max(30, geo.size.width * serviceProgress(for: car)))
                        .animation(.snappy(duration: 0.35),
                                   value: serviceProgress(for: car))
                }
            }
            .frame(height: 30)

            // Подпись «почему»: карточка пожелтела или покраснела. Кнопки
            // «Записаться» здесь больше нет (решение пользователя 08.10.2026):
            // запись — плавающей «Записаться на ТО» над таббаром, см.
            // `bookingPill`. Высота строки прежняя, метрики карточки не тронуты.
            if let hint = ServiceMath.bookingHint(kmLeft: kmUntilService(for: car)) {
                Text(hint)
                    .font(.system(size: 15))
                    .foregroundStyle(Figma.labelsSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                .frame(height: Self.bookingButtonHeight)
            }
        }
    }

    /// «Записаться на ТО» — плавающая кнопка над таббаром, как «Список» на
    /// карте (просьба пользователя 08.10.2026): запись доступна всегда, а не
    /// только когда карточка «ТО через» пожелтела. Единственный вход в
    /// запись: открывает шторку «Что расскажем сервису».
    ///
    /// На странице добавления машины кнопки нет: гаснет вместе со свайпом к
    /// ней и, погашенная, касаний не принимает.
    @ViewBuilder
    private var bookingPill: some View {
        if car != nil {
            let visible = 1 - addProgress
            Button {
                sheet = .booking
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Записаться на\u{00A0}ТО")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundStyle(Figma.labelsPrimary)
                .padding(.horizontal, 18)
                .frame(height: Self.bookingPillHeight)
                .liquidGlass(in: Capsule()) { Capsule().fill(Material.regular) }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, Self.bookingPillGap)
            .opacity(visible)
            .allowsHitTesting(visible > 0.5)
            .accessibilityHidden(visible < 0.5)
            .accessibilityHint("Покажет, что уйдёт в\u{00A0}сервис, и\u{00A0}найдёт ближайший")
        }
    }

    /// Размер и зазор до таббара — те же, что у «Список» на карте
    /// (`MapScreen.Layout.control` и `gap`).
    private static let bookingPillHeight: CGFloat = 44
    private static let bookingPillGap: CGFloat = 12

    /// Высота подписи «почему» в карточке «ТО через» и её строка вместе с
    /// зазором 12 до полосы. Имя осталось от кнопки «Записаться», которая
    /// стояла в этой строке до 08.10.2026.
    private static let bookingButtonHeight: CGFloat = 34
    private static let bookingRowHeight: CGFloat = 12 + bookingButtonHeight

    private func suggestsBooking(_ car: Car) -> Bool {
        ServiceMath.suggestsBooking(kmLeft: kmUntilService(for: car))
    }

    /// Высота карточки текущей страницы в покое. Ниже неё высоту задаёт
    /// смесь — идёт свайп; на ней самой — содержимое, как в макете.
    private var settledCardHeight: CGFloat {
        metrics(of: nearestPage).cardHeight
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
                // Цифры перетекают при смене цены и пробега.
                .contentTransition(.numericText())
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

            historyFilterChips

            if historyFilter == .trips {
                tripsStrip
            } else {
                historyStrip
            }
        }
        .padding(.vertical, 16)
    }

    /// Поездки машины карточками, как в «Ещё» (просьба пользователя
    /// 09.10.2026). Свайп влево по карточке открывает «Изменить» и
    /// «Удалить», тап — экран поездки.
    private var tripsStrip: some View {
        let shown = shownTrips
        return VStack(alignment: .leading, spacing: Self.tripGap) {
            if shown.isEmpty {
                Text("Поездок пока нет")
                    .font(.system(size: 15))
                    .foregroundStyle(Figma.vibrantSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Self.tripsEmptyHeight)
            }
            ForEach(shown) { details in
                SwipeRow(
                    onEdit: {
                        viewingTrip = details
                        tripKm = details.kmField
                        sheet = .tripDistance
                    },
                    onDelete: {
                        viewingTrip = details
                        sheet = .tripDelete
                    }
                ) {
                    Button {
                        viewingTrip = details
                        sheet = .tripDetail
                    } label: {
                        TripCard(trip: details, showsCar: false)
                    }
                    .buttonStyle(CardPressStyle())
                    .accessibilityHint("Открыть поездку")
                }
            }
        }
    }

    private func storedTrip(for details: TripDetails) -> Trip? {
        carTrips.first { $0.snapshotKey == details.snapshotKey }
            ?? cars.flatMap(\.trips).first { $0.snapshotKey == details.snapshotKey }
    }

    private func removeViewedTrip() {
        sheet = .closed
        guard let viewingTrip, let trip = storedTrip(for: viewingTrip) else { return }
        if historyCount == 1 { scrollToTop() }
        TripEdits.remove(trip, in: modelContext)
        presentToast("Поездка удалена")
    }

    private func saveTripDistance() {
        sheet = .closed
        guard let viewingTrip, let trip = storedTrip(for: viewingTrip) else { return }
        guard let meters = TripMath.meters(fromKm: tripKm) else {
            presentToast("Расстояние не изменено")
            return
        }
        TripEdits.resize(trip, to: meters, in: modelContext)
        presentToast("Расстояние обновлено!")
        addedServiceTick += 1
    }

    // MARK: - Автопробег из меню «…»

    /// Считает ли автопробег поездки этой машине. Машин несколько —
    /// только выбранной (`TripCar`), по умолчанию первой добавленной.
    private func autoCounts(_ car: Car?) -> Bool {
        guard AutoSwitch.isOn, let car else { return false }
        guard cars.count > 1 else { return true }
        let chosen = TripCar.id ?? cars.first.map(TripTracker.carID)
        return chosen == TripTracker.carID(of: car)
    }

    /// Пункт меню машины: включить автопробег для неё или выключить. Название
    /// одно на всё приложение — «Автопробег» (просьба пользователя 09.10.2026);
    /// «автоопределение» осталось именем механизма в коде (`TripAuto`).
    private func toggleAuto() {
        guard let car else { return }
        let tracker = TripTracker.shared
        if autoCounts(car) {
            tracker.setAuto(false)
            presentToast("Автопробег выключен")
        } else {
            tracker.setCar(TripTracker.carID(of: car))
            tracker.setAuto(true)
            presentToast("Автопробег включён!")
        }
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

    // MARK: - Сводка для сервиса (вариант D)

    /// Находки с названной деталью — у них есть совет. Карточка-вердикт
    /// («Похоже на неисправность») деталью не является и в сводку не идёт.
    private func partFindings(of check: EngineCheck) -> [String] {
        check.orderedFindings.filter { $0.advice != nil }.map(\.title)
    }

    /// Переходник `Car → значения` для шторки «Что расскажем сервису».
    private func bookingModel(for car: Car) -> BookingSummarySheet.Model {
        let calendar = Calendar.current
        let plate = car.plate.isEmpty ? "" : PlateFormat.format(car.plate)
        let lastService = car.sortedServices.first
        let serviceValue = lastService.map {
            ListeningSummary.Service(date: ListeningSummary.dayMonth($0.date, calendar: calendar),
                                     mileage: $0.mileage)
        }
        let check = car.lastCheck
        let findings = check.map(partFindings(of:)) ?? []
        let checkValue = check.map {
            ListeningSummary.Check(date: ListeningSummary.dayMonth($0.date, calendar: calendar),
                                   mileage: $0.mileage, findings: findings)
        }
        let checkInfo = check.map { check -> BookingSummarySheet.CheckInfo in
            let days = ListeningSummary.daysSince(check.date, now: .now, calendar: calendar)
            let at = check.mileage.map { " · на\u{00A0}\(NumberFormat.grouped($0))\u{00A0}км" } ?? ""
            // Дата — во второй строке: рядом с переключателем «Прослушивание
            // 22 сентября» не помещалось и обрезалось (кадр 25.09).
            return .init(title: "Прослушивание",
                         subtitle: "\(ListeningSummary.dayMonth(check.date, calendar: calendar)), "
                             + ListeningSummary.relative(days: days) + at,
                         findings: findings,
                         isStale: ListeningSummary.isStale(days: days))
        }
        let message = { (check: ListeningSummary.Check?) in
            ListeningSummary.message(carName: car.name, plate: plate, odometer: car.odometer,
                                     lastService: serviceValue, check: check)
        }
        return .init(
            carTitle: plate.isEmpty ? car.name : "\(car.name) · \(plate)",
            carSubtitle: "\(NumberFormat.grouped(car.odometer))\u{00A0}км · ТО через "
                + "\(NumberFormat.grouped(kmUntilService(for: car)))\u{00A0}км",
            check: checkInfo,
            lastService: lastService.map {
                (title: "Последнее ТО \(ListeningSummary.dayMonth($0.date, calendar: calendar))",
                 subtitle: "на \(NumberFormat.grouped($0.mileage))\u{00A0}км")
            },
            messageWithCheck: message(checkValue),
            messageWithoutCheck: message(nil)
        )
    }

    private static let toolbarGroupWidth: CGFloat = 104

    /// Кнопка-иконка внутри группы тулбара: 52×44, половина капсулы.
    private func toolbarIcon(_ symbol: String, label: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: Self.toolbarGroupWidth / 2, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Тулбар (нода 46165:3243)

    /// Три слота из макета: «…» слева, название по центру-слева, «Добавить ТО»
    /// справа. Системный `.toolbar`, а не своя полоса: он сам даёт безопасную
    /// зону, размытие края прокрутки, цели касания и доступность.
    @available(iOS 26.0, *)
    @ToolbarContentBuilder
    private var carToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            // «…» с системным UIMenu (UIKit): SwiftUI-Menu красил иконку
            // деструктивного пункта tint'ом вместо роли — корзина выходила
            // то синей, то белой. UIMenu рисует пункт как в системе
            // (эталон пользователя — меню виджета): текст и корзина красные.
            // Без ToolbarFade: меню доступно и до скролла — иначе машину
            // без записей ТО было не удалить вовсе.
            // На странице «Добавьте новый авто» меню гаснет: удалять там
            // нечего, а «Удалить авто» без машины выглядел анекдотом.
            EllipsisMenu(
                autoIsOn: { autoCounts(car) },
                onAuto: toggleAuto,
                onDelete: { sheet = .deleteConfirm }
            )
            .frame(width: 44, height: 44)
            .darkGlassChip(in: Circle())
            .contentShape(Circle())
            .opacity(1 - weight(of: addPageIndex))
            .allowsHitTesting(weight(of: addPageIndex) < 0.5)
            .accessibilityLabel("Действия с автомобилем")
        }
        // Системная подложка элемента бара гасится: она рисует своё стекло
        // ПОД нашей капсулой и над чёрной карточкой выходила тёмным кольцом
        // вокруг неё.
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .principal) {
            // 15pt Semibold, две строки, по левому краю — как в макете.
            // Ширина была 167 из ноды, потом 155 — просьба пользователя
            // держать 12pt до кнопки справа. Кнопка стала группой 104pt
            // вместо 139, и название на те же 35pt шире.
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
                .frame(width: 190, alignment: .leading)
                .modifier(ToolbarFade(toolbar: toolbar))
        }

        // Группа из двух кнопок в одной капсуле — «Button Group» системного
        // тулбара iOS 27 (UI Kit, нода 754:48381): «Послушать мотор» и
        // «Добавить ТО». Раньше здесь была текстовая «Добавить ТО» 139pt;
        // вторая кнопка рядом с ней в строку не влезала.
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 0) {
                toolbarIcon("waveform", label: "Послушать мотор") { sheet = .listening }
                toolbarIcon("plus", label: "Добавить ТО") { sheet = .serviceChoice }
            }
            .frame(width: Self.toolbarGroupWidth, height: 44)
            .darkGlassChip(in: Capsule())
            // Видна и до прокрутки, как «…» слева (просьба пользователя
            // 25.09.2026): послушать мотор и добавить ТО нужно и над фото, а
            // не только в прокрученном списке. Гаснет на странице «Добавить
            // авто» — там нечего слушать и некуда добавлять ТО.
            .opacity(1 - weight(of: addPageIndex))
            .allowsHitTesting(weight(of: addPageIndex) < 0.5)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    /// Подложка бара по HIG: размытие плюс градиент затемнения, оба
    /// растворяются книзу — сплошная заливка с тенью читалась как плашка,
    /// по замечанию пользователя. Живёт прозрачностью вместе с содержимым.
    private var toolbarBackdrop: some View {
        ZStack(alignment: .top) {
            // Блюр гаснет маской: резкая нижняя кромка размытия выдаёт
            // прямоугольник так же, как выдавала заливка.
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(
                        stops: [.init(color: .black, location: 0),
                                .init(color: .black, location: 0.68),
                                .init(color: .clear, location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                }

            LinearGradient(
                stops: [.init(color: .black.opacity(0.85), location: 0),
                        .init(color: .black.opacity(0.5), location: 0.55),
                        .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .frame(height: metrics.safeTop + 64)
        .ignoresSafeArea(edges: .top)
        .opacity(toolbar.isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: toolbar.isVisible)
        .allowsHitTesting(false)
    }

    /// Записи ТО вертикальным списком: дата заголовком, под ней карточка.
    ///
    /// Была горизонтальная лента 230×84 — макет `45867:3007` заменил её на
    /// список во всю ширину. Вместе с лентой ушёл `shadowInset`: запас под
    /// тени и его компенсация отрицательным отступом были нужны только
    /// потому, что горизонтальный `ScrollView` обрезал тени по своим границам.
    private var historyStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(historyItems.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Spacer(minLength: 0).frame(height: 24) }

                // Дата — заголовок группы, 16pt Semibold из макета
                Text(item.date, format: .dateTime.day(.twoDigits)
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

                switch item {
                case .service(let record):
                    // Снова contextMenu — просьба пользователя со ссылкой на HIG:
                    // при зажатии карточка приподнимается и растёт, фон
                    // затемняется, хаптик системный. Прошлое «улетает вверх»
                    // давал кастомный preview — без него система поднимает
                    // элемент на месте. Тап отдельно — сразу в правку.
                    Button { startEditing(record) } label: {
                        serviceCard(record)
                    }
                    // Тот же отклик, что у карточки прослушивания рядом: две
                    // карточки одной ленты не должны отвечать на палец по-разному.
                    .buttonStyle(CardPressStyle())
                    .contentShape(.contextMenuPreview, Self.serviceCardShape)
                    .contextMenu {
                        Button { startEditing(record) } label: {
                            Label("Изменить", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            deleteService(record)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                case .check(let check):
                    // Прослушивание правке не подлежит — оно запись того, что
                    // услышал разбор. Тап открывает шторку с тем, что тогда
                    // нашли (просьба пользователя 06.10.2026; раньше уводил
                    // в «Ошибки»), меню — удалить.
                    Button {
                        viewingCheck = .init(check)
                        sheet = .checkDetail
                    } label: {
                        checkCard(check)
                    }
                    .buttonStyle(CardPressStyle())
                    .contentShape(.contextMenuPreview, Self.serviceCardShape)
                    .contextMenu {
                        Button(role: .destructive) {
                            if historyCount == 1 { scrollToTop() }
                            modelContext.delete(check)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                    .accessibilityHint("Откроет раздел «Диагностика»")
                case .trip(let trip):
                    // Поездка в общей ленте — строкой той же высоты, что ТО и
                    // прослушивание. Тап открывает её экран, меню — то же, что
                    // по свайпу под чипсом «Поездки».
                    let details = TripDetails(trip)
                    Button {
                        viewingTrip = details
                        sheet = .tripDetail
                    } label: {
                        tripRow(details)
                    }
                    .buttonStyle(CardPressStyle())
                    .contentShape(.contextMenuPreview, Self.serviceCardShape)
                    .contextMenu {
                        Button {
                            viewingTrip = details
                            tripKm = details.kmField
                            sheet = .tripDistance
                        } label: {
                            Label("Изменить", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            viewingTrip = details
                            sheet = .tripDelete
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                    .accessibilityHint("Открыть поездку")
                }
            }
        }
    }

    /// Строка поездки — геометрия карточки прослушивания (96pt, то же
    /// стекло), зелёный значок пути: цвет поездок в приложении.
    private func tripRow(_ trip: TripDetails) -> some View {
        let places = [trip.startAddress, trip.endAddress].compactMap { $0 }
        let detail = ([trip.duration] + (places.count == 2 ? [places.joined(separator: " → ")] : []))
            .joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Figma.accentsGreen)
                Text("Поездка · \(trip.distance)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(height: 20)

            Text(detail)
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
        .frame(height: Self.serviceCardHeight)
        .darkGlassCard(in: Self.serviceCardShape)
        .contentShape(Self.serviceCardShape)
    }

    /// «Всё / ТО / Прослушивания / Поездки» над лентой — капсулами, как фильтры
    /// приложения; выбранная — белая. Смена фильтра меняет высоту ленты, и
    /// она анимируется вместе с содержимым.
    private var historyFilterChips: some View {
        HStack(spacing: 8) {
            ForEach(HistoryFilter.allCases, id: \.self) { filter in
                let isOn = historyFilter == filter
                Button {
                    withAnimation(.snappy(duration: 0.3)) { historyFilter = filter }
                } label: {
                    Text(filter.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isOn ? Color.black : .white)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(Figma.fillsTertiary),
                                    in: Capsule())
                        // Видно 32, нажимается 44 — HIG.
                        .contentShape(Rectangle().inset(by: -6))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 32)
        .sensoryFeedback(.selection, trigger: historyFilter)
    }

    /// Карточка прослушивания — той же геометрии, что карточка ТО (96pt,
    /// то же стекло), чтобы лента читалась одной хронологией. Отличается
    /// жёлтой волной в заголовке: цвет прослушиваний в приложении.
    private func checkCard(_ check: EngineCheck) -> some View {
        let findings = partFindings(of: check)
        let lastService = services.first { $0.date <= check.date }
        let after = ListeningSummary.kmAfterService(checkMileage: check.mileage,
                                                    lastServiceMileage: lastService?.mileage)
        let head = ["Прослушивание",
                    check.mileage.map { "\(NumberFormat.grouped($0))\u{00A0}км" }]
            .compactMap { $0 }.joined(separator: " · ")
        let detail = [findings.isEmpty ? "Явных неисправностей нет" : findings.joined(separator: ", "),
                      after.map { "\(NumberFormat.grouped($0))\u{00A0}км после ТО" }]
            .compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Figma.accentsYellow)
                Text(head)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(height: 20)

            Text(detail)
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
        .frame(height: Self.serviceCardHeight)
        .darkGlassCard(in: Self.serviceCardShape)
        .contentShape(Self.serviceCardShape)
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
            Text(ServiceMath.cardHeadline(amount: record.amount, mileage: record.mileage))
                .font(.system(size: 15, weight: .semibold))
                // Трекинг снят по той же причине, что у даты и значений плиток.
                .foregroundStyle(.white)
                // Сумма с пробегом длиннее одной суммы: строка ужимается, а
                // не переносится — высота 20 второй строки не вместит.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 20)

            // Две строки по 18 — так работы и стоят в макете; у записи с одной
            // работой строка остаётся сверху, а карточка держит свои 96.
            Text(ServiceMath.cardSubtitle(works: record.works.map(\.title)))
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
    /// Процесс (`.progress`) не гаснет сам — его закрывает следующий тост
    /// или `hideToast()`; ошибке даётся больше времени, её читают.
    private func presentToast(_ message: String, kind: ToastKind = .success) {
        toastMessage = message
        toastKind = kind
        toastTask?.cancel()
        showToast = true
        AccessibilityNotification.Announcement(message).post()

        guard kind != .progress else { return }
        let dwell: Duration = kind == .error ? .milliseconds(3500) : Motion.toastDwell
        toastTask = Task {
            try? await Task.sleep(for: dwell)
            guard !Task.isCancelled else { return }
            showToast = false
        }
    }

    private func hideToast() {
        toastTask?.cancel()
        showToast = false
    }

    /// Figma «сакцесс» → «Notification - Collapsed», аннотация «Хаптик позитивное действие».
    /// Тот же тост несёт процессы (спиннер) и ошибки (красный знак) — по
    /// просьбе пользователя единый механизм статусов поиска и добавления.
    private var toast: some View {
        HStack(spacing: 10) {
            switch toastKind {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Figma.accentsGreen)
            case .progress:
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Figma.accentsRed)
            }

            Text(toastMessage)
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.23)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // По ширине надписи (нода 45887:3742). Одного maxWidth мало:
        // frame(maxWidth:) не обнимает контент, а растягивается до потолка
        // предложением родителя — потому «узкий» тост оставался широким.
        // Успех и процесс — строго по тексту; ошибка переносится в 320.
        .fixedSize(horizontal: toastKind != .error, vertical: true)
        .frame(maxWidth: 320)
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

    /// Цвет светофора: зелёный — далеко, жёлтый — за 5 000 км, красный —
    /// за 1 000 (пороги в `ServiceMath`).
    private func urgencyColor(for car: Car) -> Color {
        switch ServiceMath.urgency(kmLeft: kmUntilService(for: car)) {
        case .normal: Figma.accentsGreen
        case .soon: Figma.accentsYellow
        case .urgent: Figma.accentsRed
        }
    }

    /// Прогресс интервала: сколько из 10 000 км уже проехали.
    private func serviceProgress(for car: Car) -> Double {
        ServiceMath.progress(odometer: car.odometer,
                             serviceMileages: car.services.map(\.mileage))
    }

    /// Разбор фото/PDF: скрипт достаёт базовые показатели и форма открывается
    /// уже заполненной — ручной ввод с нуля здесь неуместен.
    /// TODO: заменить заглушку на реальный парсер.
    /// Открывает форму ТО с тем, что удалось вычитать из бланка. Пустой
    /// разбор — честная пустая форма с сегодняшней датой и текущим пробегом:
    /// приложить нечитаемое фото чеком всё равно можно.
    private func applyParsedService(_ parsed: ParsedServiceDoc?) {
        if let parsed, let d = parsed.day, let m = parsed.month, let y = parsed.year,
           let date = Calendar.current.date(from: DateComponents(year: y, month: m, day: d)) {
            serviceDate = date
        } else {
            serviceDate = Date()
        }
        serviceMileage = NumberFormat.grouped(parsed?.mileage ?? odometer)
        let parsedWorks = (parsed?.works ?? []).map {
            ServiceWork(title: $0.title, amount: NumberFormat.grouped($0.amount))
        }
        works = parsedWorks.isEmpty ? [ServiceWork()] : parsedWorks
        sheet = .service
    }

    /// Считывает бланк из выбранного файла («Файлы»: PDF или изображение),
    /// кладёт превью в чеки и открывает заполненную форму.
    private func importServiceDocument(_ url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        Task {
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            let parsed: ParsedServiceDoc?
            if url.pathExtension.lowercased() == "pdf" {
                parsed = await ServiceDocScanner.parse(pdfURL: url)
                if let preview = ServiceDocScanner.preview(pdfURL: url) {
                    photos = [preview]
                }
            } else if let data = try? Data(contentsOf: url),
                      let image = await ImageLoader.decode([data]).first {
                photos = [image]
                parsed = await ServiceDocScanner.parse(image: image)
            } else {
                parsed = nil
            }
            guard !Task.isCancelled else { return }
            applyParsedService(parsed)
        }
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

        // По номеру: раньше поиск шёл молча и на любой исход просто ничего
        // не происходило. Теперь процесс виден тостом, находка проходит через
        // «Это ваш автомобиль?» (как на первом входе), ошибки называются.
        if tab == 0 {
            guard PlateFormat.isValid(plate) else {
                presentToast("Проверьте номер", kind: .error)
                return
            }
            presentToast("Ищем машину по номеру…", kind: .progress)
            Task {
                do {
                    let vehicle = try await lookup.lookup(plate: plate)
                    hideToast()
                    foundCar = FoundCar(plate: plate, vehicle: vehicle)
                    sheet = .carFound
                } catch let error as URLError where error.code != .cancelled {
                    presentToast("Нет соединения — попробуйте ещё раз",
                                 kind: .error)
                } catch {
                    presentToast("Машина по этому номеру не нашлась",
                                 kind: .error)
                }
            }
            return
        }

        guard !name.isEmpty else { return }
        insert(Car(plate: "", name: name, odometer: mileage,
                   price: price, photo: photoData))
    }

    /// Подтверждение из шторки «Это ваш автомобиль?»: только здесь найденное
    /// становится машиной. Тост о добавлении — процесс вставки мгновенный,
    /// но без него добавление выглядит как «шторка просто закрылась».
    ///
    /// Своё фото сюда не приходит вовсе, и это правило, а не упущение: поиск
    /// по номеру возвращает поколение, по нему находится кадр каталога, и
    /// `car.photo` этот кадр перебил бы. Форма снимок по номеру и не
    /// предлагает, но поля у вкладок общие: выбранное на «По названию»
    /// дожило бы сюда после переключения вкладки и прицепилось невидимо.
    /// Поэтому ветка закрыта здесь, а не только отсутствием кнопки.
    private func confirmFoundCar() {
        guard let found = foundCar else { return }
        let price = NumberFormat.digits(carPrice)
        insert(Car(plate: PlateFormat.format(carPlate), name: found.name,
                   vin: found.vehicle.displayVIN,
                   generation: found.vehicle.generation,
                   odometer: found.vehicle.odometer ?? 0,
                   price: price, photo: nil))
        foundCar = nil
        sheet = .closed
        presentToast("Машина добавлена!")
        addedServiceTick += 1
    }

    private func insert(_ car: Car) {
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

    private func deleteCar() {
        guard let car else { return }
        // После удаления машин станет на одну меньше — страницу подтягиваем,
        // иначе карусель окажется за последней страницей.
        carPage = max(0, min(carPage, cars.count - 2))
        // Кадры карт поездок лежат в кэше мимо базы — каскад их не уберёт,
        // а на них маршруты удаляемой машины.
        car.trips.forEach { TripSnapshots.remove(for: $0.snapshotKey) }
        // Напоминание о ТО живёт в системной очереди и в настройках — тоже
        // мимо базы.
        ServiceReminder.forget(id: ServiceReminder.key(createdAt: car.createdAt))
        // ТО, чеки, прослушивания и поездки уходят каскадом — правила заданы
        // в модели `Car`.
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
    /// Карточка подтверждения удаления машины. Текст и кнопка — на
    /// системном материале со скруглением, как модалка удаления в «Фото»
    /// (эталон пользователя). Кнопка одна и красная; передумать — тап мимо.
    private var deleteConfirmModal: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { sheet = .closed }

            VStack(spacing: 20) {
                Text("Машина удалится вместе с\u{00A0}историей ТО, прослушиваниями "
                     + "и\u{00A0}поездками. Вернуть её нельзя.")
                    .font(.system(size: 17))
                    .tracking(-0.43)
                    .figmaLineHeight(22, fontSize: 17)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    sheet = .closed
                    deleteCar()
                } label: {
                    Text("Удалить авто")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Figma.accentsRed)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Figma.fillsTertiary, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Удалить авто безвозвратно")
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .environment(\.colorScheme, .dark)
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
        }
    }

    /// Удаление записи ТО. С последней записью истории список пустеет и
    /// вертикальный скролл отключается (`scrollDisabled(historyCount == 0)`)
    /// — если он в этот момент был прокручен, страница застывала со сдвигом
    /// и «скролл блокировался» (замечание пользователя). Сначала наверх,
    /// потом удалять. То же у прослушивания и поездки.
    private func deleteService(_ record: ServiceRecord) {
        if historyCount == 1 { scrollToTop() }
        // Работы уходят каскадом — правило в модели
        modelContext.delete(record)
    }

    private func startEditing(_ record: ServiceRecord) {
        serviceDate = record.date
        serviceMileage = NumberFormat.grouped(record.mileage)
        // Форма рассчитана минимум на одну группу полей: пустой список её ломает
        let rows = record.works.map { ServiceWork(title: $0.title, amount: NumberFormat.grouped($0.amount)) }
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

/// Содержимое тулбара появляется прозрачностью. Сам бар существует всегда:
/// переключение его видимости меняло инсеты прокрутки скачком — позиция
/// «возвращалась сменой кадра».
/// Кнопка «…» с настоящим системным меню. UIKit, а не SwiftUI-Menu:
/// только UIMenu рисует деструктивный пункт по-системному — красными и
/// текстом, и корзиной. Будущие действия добавляются в массив children.
private struct EllipsisMenu: UIViewRepresentable {
    /// Считает ли автопробег поездки этой машине — от этого подпись
    /// пункта: «Включить…» или «Выключить…».
    let autoIsOn: () -> Bool
    let onAuto: () -> Void
    let onDelete: () -> Void

    /// Меню собирается один раз, а машина под ним меняется (карусель):
    /// действия лежат здесь и обновляются с каждой перерисовкой, иначе пункт
    /// работал бы с машиной, которая была на экране при создании кнопки.
    final class Coordinator {
        var autoIsOn: () -> Bool = { false }
        var onAuto: () -> Void = {}
        var onDelete: () -> Void = {}
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIButton {
        let coordinator = context.coordinator
        refresh(coordinator)
        let button = UIButton(type: .system)
        let icon = UIImage(systemName: "ellipsis",
                           withConfiguration: UIImage.SymbolConfiguration(
                               pointSize: 18, weight: .semibold))
        button.setImage(icon, for: .normal)
        button.tintColor = .white
        button.showsMenuAsPrimaryAction = true
        // Пункт собирается при каждом открытии меню: его подпись зависит от
        // того, включён ли автопробег сейчас.
        let auto = UIDeferredMenuElement.uncached { [weak coordinator] completion in
            guard let coordinator else {
                completion([])
                return
            }
            let isOn = coordinator.autoIsOn()
            completion([
                UIAction(title: isOn ? "Выключить автопробег" : "Включить автопробег",
                         image: UIImage(systemName: isOn ? "location.slash" : "location")) { _ in
                    coordinator.onAuto()
                },
            ])
        }
        let delete = UIAction(title: "Удалить авто",
                              image: UIImage(systemName: "trash"),
                              attributes: .destructive) { [weak coordinator] _ in
            coordinator?.onDelete()
        }
        // Удаление — отдельной группой, под чертой: рядом с обычным пунктом
        // в него легко попасть мимо.
        button.menu = UIMenu(children: [auto, UIMenu(options: .displayInline, children: [delete])])
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        refresh(context.coordinator)
    }

    private func refresh(_ coordinator: Coordinator) {
        coordinator.autoIsOn = autoIsOn
        coordinator.onAuto = onAuto
        coordinator.onDelete = onDelete
    }
}

/// Модалки поездки с главной: экран поездки, подтверждение удаления и
/// правка расстояния. Отдельным модификатором, чтобы цепочка у `body` не
/// росла: она и так на пределе проверки типов.
private struct TripModals: ViewModifier {
    let trip: TripDetails?
    let showDetail: Binding<Bool>
    let showDelete: Binding<Bool>
    let showDistance: Binding<Bool>
    @Binding var km: String
    let onDelete: () -> Void
    let onSaveDistance: () -> Void
    let onClose: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: showDetail) {
                if let trip {
                    TripSheet(trip: trip, onDelete: onDelete, onClose: onClose)
                }
            }
            .confirmationDialog("Удалить поездку?", isPresented: showDelete,
                                titleVisibility: .visible) {
                Button("Удалить", role: .destructive, action: onDelete)
            } message: {
                if let km = trip?.kmBack, km > 0 {
                    Text("Пробег уменьшится на\u{00A0}\(NumberFormat.grouped(km))\u{00A0}км")
                }
            }
            .alert("Расстояние поездки", isPresented: showDistance) {
                TextField("км", text: $km)
                    .keyboardType(.decimalPad)
                Button("Сохранить", action: onSaveDistance)
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Пробег пересчитается")
            }
    }
}

private struct ToolbarFade: ViewModifier {
    @ObservedObject var toolbar: ToolbarVisibility

    func body(content: Content) -> some View {
        content
            .opacity(toolbar.isVisible ? 1 : 0)
            // Погашенная кнопка не должна ловить тапы вслепую.
            .allowsHitTesting(toolbar.isVisible)
            .animation(.easeInOut(duration: 0.18), value: toolbar.isVisible)
    }
}

/// Поднимается по иерархии UIKit до ближайшего UIScrollView — того самого,
/// на котором стоит SwiftUI-прокрутка. Отдельного файла не заводим: правка
/// `project.pbxproj` вручную дороже двадцати строк.
private extension View {
    /// Карточки главной — общий `darkCardSurface` (см. LiquidGlass.swift):
    /// нарисованная заливка с кромкой white 10 %, единый вид с «Ошибками»
    /// без живого стекла на каждом элементе списка.
    func darkGlassCard<S: Shape>(in shape: S) -> some View {
        darkCardSurface(in: shape)
    }

    /// Кнопки тулбара остаются настоящим стеклом: их две, они висят поверх
    /// уезжающего контента, и преломление там осмысленно — в отличие от
    /// карточек на чёрном фоне.
    ///
    /// Тонировка полупрозрачная: сплошной #1A1A1A глушил стекло целиком, и на
    /// iPhone (iOS 27) кнопки при прокрутке выглядели просто тёмными кругами
    /// (вопрос пользователя 27.09.2026). Фолбэк без стекла — прежний.
    func darkGlassChip<S: Shape>(in shape: S) -> some View {
        liquidGlass(in: shape, tint: Figma.darkCard.opacity(0.35)) {
            shape.fill(Figma.darkCard)
                .overlay(shape.stroke(Color.white.opacity(0.10), lineWidth: 0.5))
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


/// Запись общей ленты «История обслуживания»: ТО, прослушивание или поездка.
private enum HistoryItem: Identifiable {
    case service(ServiceRecord)
    case check(EngineCheck)
    case trip(Trip)

    var id: PersistentIdentifier {
        switch self {
        case .service(let record): record.persistentModelID
        case .check(let check): check.persistentModelID
        case .trip(let trip): trip.persistentModelID
        }
    }

    var date: Date {
        switch self {
        case .service(let record): record.date
        case .check(let check): check.date
        case .trip(let trip): trip.startedAt
        }
    }
}

private enum HistoryFilter: CaseIterable {
    /// «Всё» — ТО, прослушивания и поездки; «Поездки» — те же поездки
    /// карточками с картой.
    case all, services, checks, trips

    var title: String {
        switch self {
        case .all: "Всё"
        case .services: "ТО"
        case .checks: "Прослушивания"
        case .trips: "Поездки"
        }
    }
}
