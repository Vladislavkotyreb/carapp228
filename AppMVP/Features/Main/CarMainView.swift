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

    /// Отрезок появления. В покое шапки нет: на её месте стоит заголовок самой
    /// страницы, который при прокрутке уходит под неё.
    static let fadeStart: CGFloat = 8
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
    @State private var showToast = false
    @State private var showDeleteConfirm = false
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

    /// Гасим сам распознаватель, а не `isScrollEnabled`: последним управляет
    /// SwiftUI из окружения и может перезаписать его на любом обновлении, а
    /// `body` во время свайпа пересобирается каждый кадр из-за `dragX`.
    /// Профиль отказа при этом правильный: если правку всё-таки затрут,
    /// вернётся нынешнее поведение, а не мёртвая прокрутка.
    private func setScrollEnabled(_ enabled: Bool) {
        scroll.view?.panGestureRecognizer.isEnabled = enabled
    }


    /// Межсервисный интервал: ТО через 10 000 км от последнего.
    private let serviceInterval = 10_000

    /// Прогресс свайпа: 0 — машина, 1 — «добавить новую».
    /// Аннотация макета 45895:3569 — «все элементы остаются на месте и просто
    /// меняются надписи», поэтому страница неподвижна, едет только фото.
    private func swipeProgress(width: CGFloat) -> Double {
        guard width > 0 else { return Double(carPage) }
        return min(1, max(0, Double(CGFloat(carPage) - dragX / width)))
    }

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
                let atEdge = (carPage == 0 && dx > 0) || (carPage == 1 && dx < 0)
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
                if value.translation.width < -threshold { page = min(1, carPage + 1) }
                if value.translation.width > threshold { page = max(0, carPage - 1) }
                withAnimation(Motion.page) {
                    carPage = page
                    dragX = 0
                }
            }
    }

    private var car: Car? { cars.first }
    private var services: [ServiceRecord] { car?.sortedServices ?? [] }
    private var odometer: Int { car?.odometer ?? 0 }

    // Поля шторки «Добавление ТО»
    @State private var serviceDate = Date()
    @State private var serviceMileage = ""
    @State private var works: [ServiceWork] = [ServiceWork()]
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photos: [UIImage] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Карусель авто: интерактивный пейджинг свайпом влево/вправо.
            // TabView не используем — он добавляет свои отступы и ломает координаты макета.
            // Аннотация макета (45895:3569): «все элементы остаются на месте и просто
            // меняются надписи» — раскладка страниц идентична, разъезжаться нечему.
            GeometryReader { geo in
                let width = geo.size.width
                // Прогресс свайпа 0…1. Страница НЕ едет: он управляет только
                // содержимым — фото, текстами и видимостью блоков.
                let p = swipeProgress(width: width)

                Group {
                    if services.isEmpty {
                        emptyState(progress: p)
                    } else {
                        filledState(progress: p)
                    }
                }

                // simultaneousGesture, а не gesture: заполненная страница —
                // вертикальный ScrollView, и он забирал свайп себе, поэтому
                // над картинкой машины и карточкой ТО карусель не листалась.
                .simultaneousGesture(carouselDrag(width: width))
            }
            // важно: сам GeometryReader должен игнорировать safe area, иначе он
            // отдаёт урезанный размер и все координаты макета съезжают вниз
            .ignoresSafeArea()

            // В макете таббар стоит на y = 779 при высоте экрана 874, то есть
            // в 7pt над home indicator. Прижимаем к нижней safe area, чтобы
            // этот зазор сохранялся на экранах любой высоты.
            FloatingTabBar(selection: $tab)
                .frame(maxWidth: .infinity)
                .offset(y: metrics.bottomAnchoredY(designY: 779, height: 54))

            if showToast {
                toast
                    .frame(maxWidth: .infinity)
                    .offset(y: 62)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

        }
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
                date: $serviceDate,
                mileage: $serviceMileage,
                works: $works,
                photoItems: $photoItems,
                photos: $photos,
                onClose: { showAddService = false },
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
            carPage: $carPage,
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
        .animation(Motion.toast, value: showToast)
        .sensoryFeedback(.success, trigger: services.count)
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

    // MARK: - «главная» — авто без ТО

    private func emptyState(progress p: Double) -> some View {
        let visible = 1 - p
        return VStack(alignment: .leading, spacing: 32) {
            VStack(spacing: 24) {
                header(progress: p, stretches: false)

                Button { p > 0.5 ? (showAddCar = true) : (showServiceChoice = true) } label: {
                    darkCard(title: "Добавить ТО", altTitle: "Добавить авто", progress: p)
                }
                    .buttonStyle(.plain)
                    .accessibilityLabel(p > 0.5 ? "Добавить авто" : "Добавить ТО")

                // Белые карточки уходят целиком: на странице «добавить новую»
                // (нода 45949:3265) их нет вовсе, остаётся одна тёмная.
                HStack(spacing: 16) {
                    statCard(title: "Цена авто", value: "4 269 999 ₽ ")
                    statCard(title: "Пробег", value: "\(formattedNumber(odometer)) км ")
                }
                .opacity(visible)
            }

            deleteButton()
                .opacity(visible)
                // Погашенная вьюха в SwiftUI продолжает принимать касания —
                // без этого на странице добавления авто можно нажать
                // невидимое «Удалить авто».
                .allowsHitTesting(visible > 0.5)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 723, alignment: .top)
        .offset(y: 103)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) { gradientLayer }
    }

    // MARK: - «главная_то_добавлено»

    private func filledState(progress p: Double) -> some View {
        let visible = 1 - p
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                header(progress: p, stretches: true)

                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        // На второй странице карточка превращается в кнопку
                        // добавления авто; при p = 0 это просто сводка.
                        Button { if p > 0.5 { showAddCar = true } } label: {
                            nextServiceCard(progress: p)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(p > 0.5 ? "Добавить авто" : "ТО через")

                        // Белые карточки уходят целиком: на странице
                        // «добавить новую» их нет вовсе.
                        HStack(spacing: 16) {
                            statCard(title: "Цена авто", value: "4 269 999 ₽ ")
                            statCard(title: "Пробег", value: "\(formattedNumber(odometer)) км ")
                        }
                        .opacity(visible)
                    }

                    historyCard()
                        .opacity(visible)
                        // Погашенная вьюха продолжает принимать касания —
                        // иначе «Добавить ТО» внутри неё нажимается вслепую.
                        .allowsHitTesting(visible > 0.5)

                    deleteButton()
                        .opacity(visible)
                        .allowsHitTesting(visible > 0.5)
                }
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
                .onChange(of: offset) { _, new in scroll.offset = new }
        }
    }

    // MARK: - Шапка при прокрутке

    /// Figma «header» (46001:6457): чёрная плашка 402×137 поверх статус-бара,
    /// контент прижат к низу — название модели и уменьшенный номер.
    private func scrollHeader(progress p: Double) -> some View {
        VStack(spacing: 6) {
            // Высота 22 (leading/headline) вместо figmaLineHeight: строка
            // одна, и Figma центрирует её в line box — то же самое делает
            // фиксированная высота.
            //
            // Трекинга нет намеренно: токен Headline объявляет −0.43, но нода
            // отрисована без него. Ширина ноды 208 — это ровно ширина строки
            // с трекингом 0 (208.02), с −0.43 вышло бы 197.
            Text(Self.carTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(height: 22)

            compactPlate
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
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

    /// Номер в шапке — не тот же `plate`, а уменьшенная копия (46001:6482):
    /// 11pt против 17, паддинги 6/2 против 12/4, разделитель 0.5pt.
    private var compactPlate: some View {
        HStack(spacing: 2) {
            HStack(spacing: 4) {
                Text("В")
                Text("777")
                Text("ОР")
            }

            Rectangle()
                .fill(Figma.labelsVibrantTertiary)
                .frame(width: 0.5, height: 20.117)
                .blendMode(.softLight)

            Text("777")
        }
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.06)
        .foregroundStyle(Figma.graysGray2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Figma.fillsPrimary, in: RoundedRectangle(cornerRadius: 12))
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
                        title(Self.carTitle).opacity(1 - p)
                        title("Добавьте новый авто").opacity(p)
                    }

                    plate.opacity(1 - p)
                }

                // Единственный едущий элемент. Локальный GeometryReader
                // намеренно: он принимает предложенную ширину контентной
                // области (370), а не экранную. Раньше здесь стояла
                // width * 2 от ширины экрана, и вся раскладка вылезала
                // за края на 16pt с каждой стороны.
                GeometryReader { g in
                    HStack(spacing: 0) {
                        carPhoto.frame(width: g.size.width)
                        carPhoto.frame(width: g.size.width)
                    }
                    .offset(x: -CGFloat(p) * g.size.width)
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

            pageControl(addNew: p > 0.5)
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

    private var carPhoto: some View {
        Image("CarPhoto")
            .resizable()
            .scaledToFit()
            .frame(width: 295.736, height: 152.196)
            .frame(maxWidth: .infinity)
    }

    private var plate: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                Text("В")
                Text("777")
                Text("ОР")
            }

            Rectangle()
                .fill(Figma.separatorsVibrant)
                .frame(width: 1, height: 20.117)
                .blendMode(.softLight)

            Text("777")
        }
        .font(.system(size: 17, weight: .semibold))
        .tracking(-0.43)
        .foregroundStyle(Figma.graysGray2)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 32)
        .background(Figma.fillsPrimary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func pageControl(addNew: Bool) -> some View {
        HStack(spacing: 8) {
            // Точка не исчезает, а гаснет до Fills/Primary
            Circle()
                .fill(addNew ? Figma.fillsPrimary : .white)
                .frame(width: 8, height: 8)

            incrementGlyph(active: addNew)
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

    /// Кнопка-карточка 92pt. Надписи перекрёстно меняются, подложка целая.
    private func darkCard(title: String, altTitle: String,
                          progress: Double) -> some View {
        addLabel(title, altTitle: altTitle, progress: progress)
        .padding(24)
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        // Figma 45867:2944 — системный «Liquid Glass - Regular - Medium».
        // Кромку даёт стекло, а не нарисованная обводка; раньше здесь
        // расходились радиусы заливки (36) и обводки (34).
        .liquidGlass(in: RoundedRectangle(cornerRadius: 36), tint: Figma.darkCard) {
            RoundedRectangle(cornerRadius: 36)
                .fill(Figma.darkCard)
                .overlay(RoundedRectangle(cornerRadius: 36)
                    .stroke(Color(white: 166 / 255), lineWidth: 0.5))
        }
        .motionRim(in: RoundedRectangle(cornerRadius: 36))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
    }

    /// Карточка «ТО через» с прогрессом (Figma 45867:3026). На странице
    /// «добавить новую» подложка остаётся ровно на месте, а содержимое
    /// перекрёстно меняется на «+ Добавить авто» (нода 45949:3288) — тот же
    /// принцип, что и у статичной карусели. Высоту задаёт «ТО через»:
    /// он заведомо выше подписи, поэтому ZStack ничего не двигает.
    private func nextServiceCard(progress p: Double) -> some View {
        ZStack {
            serviceProgressContent.opacity(1 - p)
            addLabel("Добавить авто").opacity(p)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        // Figma 45867:2944 — системный «Liquid Glass - Regular - Medium».
        // Кромку даёт стекло, а не нарисованная обводка; раньше здесь
        // расходились радиусы заливки (36) и обводки (34).
        .liquidGlass(in: RoundedRectangle(cornerRadius: 36), tint: Figma.darkCard) {
            RoundedRectangle(cornerRadius: 36)
                .fill(Figma.darkCard)
                .overlay(RoundedRectangle(cornerRadius: 36)
                    .stroke(Color(white: 166 / 255), lineWidth: 0.5))
        }
        .motionRim(in: RoundedRectangle(cornerRadius: 36))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
    }

    private var serviceProgressContent: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("ТО через")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.08)
                    .foregroundStyle(Figma.vibrantPrimary)

                Text("\(formattedNumber(kmUntilService)) км ")
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
                        .frame(width: geo.size.width * serviceProgress)
                }
            }
            .frame(height: 30)
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.08)
                .foregroundStyle(Figma.vibrantSecondary)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.45)
                .foregroundStyle(Figma.labelsPrimary)
        }
        .frame(height: 47)
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        // Figma: 0/0/32 #EBEBEB — мягкая подложка, а не свечение вокруг плитки
        .background(
            RoundedRectangle(cornerRadius: 34)
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
        )
    }

    /// Figma «Frame 2608897» (45893:3541): вся история в одной белой карточке
    /// 370×350, padding 16, radius 34, тень 0/0/32 #EBEBEB.
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

            // «Добавить ТО» внутри карточки — синяя, на Fills/Tertiary
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 34)
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
        )
    }

    /// Лента карточек ТО 230×84; следующая карточка выглядывает справа.
    private var historyStrip: some View {
        // ScrollView клипует контент, поэтому даём тени запас внутри
        // и компенсируем его отрицательным отступом снаружи.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(services) { record in
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
                    .frame(width: 230, height: 84)
                    .background(
                        RoundedRectangle(cornerRadius: 34)
                            .fill(.white)
                            .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
                    )
                }
            }
            .padding(shadowInset)
        }
        .frame(height: 84 + shadowInset * 2)
        .padding(-shadowInset)
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

    /// Figma «сакцесс» → «Notification - Collapsed», аннотация «Хаптик позитивное действие».
    private var toast: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(Figma.accentsGreen)

            Text("ТО добавлено!")
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
    private var lastServiceMileage: Int {
        services.map(\.mileage).max() ?? odometer
    }

    /// «ТО через N км» — остаток до следующего сервиса.
    private var kmUntilService: Int {
        max(0, lastServiceMileage + serviceInterval - odometer)
    }

    /// Прогресс интервала: сколько из 10 000 км уже проехали.
    private var serviceProgress: Double {
        let driven = Double(odometer - lastServiceMileage)
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

    private func deleteCar() {
        guard let car else { return }
        // ТО и чеки уходят каскадом — правило задано в модели Car.services
        modelContext.delete(car)
    }

    private func saveService() {
        guard let car else { return }
        let mileage = Int(serviceMileage.filter(\.isNumber)) ?? odometer

        let record = ServiceRecord(date: serviceDate, mileage: mileage)
        record.works = works.compactMap { work in
            let amount = Int(work.amount.filter(\.isNumber)) ?? 0
            let title = work.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty || amount > 0 else { return nil }
            return ServiceWorkItem(title: title, amount: amount)
        }
        record.car = car
        modelContext.insert(record)

        // Одометр не может быть меньше пробега на последнем ТО
        car.odometer = max(car.odometer, mileage)

        showAddService = false
        serviceMileage = ""
        works = [ServiceWork()]

        showToast = true
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            showToast = false
        }
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
    @Binding var carPage: Int
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
                    photoItems: $photoItems,
                    onClose: { showAddCar = false },
                    onSubmit: {
                        showAddCar = false
                        carPage = 0
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
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
