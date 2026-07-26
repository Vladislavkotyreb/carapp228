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


    /// Межсервисный интервал: ТО через 10 000 км от последнего.
    private let serviceInterval = 10_000

    /// Насколько сдвинуть элемент внутри страницы, чтобы он визуально стоял
    /// на месте, пока карусель едет. Нужно точкам пейдж-контрола.
    private func pinX(_ index: Int, _ width: CGFloat, _ containerX: CGFloat) -> CGFloat {
        -(CGFloat(index) * width + containerX)
    }

    /// Видимость варианта точек этой страницы: пока страницы разъезжаются,
    /// «точка» и «плюс» перекрестно гаснут и не наложатся двумя копиями.
    private func visibility(_ index: Int, _ width: CGFloat, _ containerX: CGFloat) -> Double {
        guard width > 0 else { return index == 0 ? 1 : 0 }
        return Double(max(0, 1 - abs(CGFloat(index) * width + containerX) / width))
    }

    private enum SwipeAxis { case horizontal, vertical }

    /// Порог, после которого решаем, куда ведёт жест.
    private static let axisLockThreshold: CGFloat = 10

    private func carouselDrag(width: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height

                if swipeAxis == nil,
                   max(abs(dx), abs(dy)) > Self.axisLockThreshold {
                    swipeAxis = abs(dx) > abs(dy) ? .horizontal : .vertical
                }
                guard swipeAxis == .horizontal else { return }

                // у краёв карусели тянется туже
                let atEdge = (carPage == 0 && dx > 0) || (carPage == 1 && dx < 0)
                dragX = atEdge ? dx / 3 : dx
            }
            .onEnded { value in
                defer { swipeAxis = nil }
                guard swipeAxis == .horizontal else { return }

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
                // Экранное смещение контейнера. Страница i стоит в
                // x = i * width + containerX, отсюда компенсация для точек.
                let width = geo.size.width
                let containerX = -CGFloat(carPage) * width + dragX

                HStack(spacing: 0) {
                    Group {
                        if services.isEmpty {
                            emptyState(pin: pinX(0, width, containerX),
                                       visible: visibility(0, width, containerX))
                        } else {
                            filledState(pin: pinX(0, width, containerX),
                                        visible: visibility(0, width, containerX))
                        }
                    }
                    .frame(width: width)

                    addNewCarState(pin: pinX(1, width, containerX),
                                   visible: visibility(1, width, containerX))
                        .frame(width: width)
                }
                .offset(x: containerX)
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
        .confirmationDialog("Удалить авто?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { deleteCar() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("История обслуживания тоже будет удалена.")
        }
    }

    // MARK: - «главная» — авто без ТО

    private func emptyState(pin: CGFloat, visible: Double) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(spacing: 24) {
                header(addNew: false, pin: pin, visible: visible)

                Button { showServiceChoice = true } label: { addServiceCard }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Добавить ТО")

                HStack(spacing: 16) {
                    statCard(title: "Цена авто", value: "4 269 999 ₽ ")
                    statCard(title: "Пробег", value: "\(formattedNumber(odometer)) км ")
                }
            }

            deleteButton
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 723, alignment: .top)
        .offset(y: 103)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) { gradientLayer }
    }

    // MARK: - «главная_то_добавлено»

    private func filledState(pin: CGFloat, visible: Double) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                header(addNew: false, pin: pin, visible: visible)

                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        nextServiceCard

                        HStack(spacing: 16) {
                            statCard(title: "Цена авто", value: "4 269 999 ₽ ")
                            statCard(title: "Пробег", value: "\(formattedNumber(odometer)) км ")
                        }
                    }

                    historyCard

                    deleteButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 103)
            .padding(.bottom, 140)
            .background(alignment: .top) { gradientLayer }
        }
        // HIG: форму со списком клавиатура должна отпускать скроллом
        .scrollDismissesKeyboard(.interactively)
        // пока жест признан горизонтальным, список не должен ползти
        .scrollDisabled(swipeAxis == .horizontal)
    }

    // MARK: - «главная_добавить новую» — вторая страница карусели

    private func addNewCarState(pin: CGFloat, visible: Double) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(spacing: 24) {
                header(addNew: true, pin: pin, visible: visible)

                Button { showAddCar = true } label: {
                    darkCard(symbol: "plus", title: "Добавить авто")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Добавить авто")
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 723, alignment: .top)
        .offset(y: 103)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) { gradientLayer }
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

    private func header(addNew: Bool, pin: CGFloat, visible: Double) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Text(addNew ? "Добавьте новый авто" : "Mercedes-Benz GL-класс")
                        .font(.system(size: 26, weight: .bold))
                        .figmaLineHeight(31.2, fontSize: 26, weight: .bold)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    // Номер не убирается, а гасится в 0 — элементы остаются на месте
                    plate
                        .opacity(addNew ? 0 : 1)
                }

                Image("CarPhoto")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 295.736, height: 152.196)
                    .frame(maxWidth: .infinity)
                    .frame(height: 190.415)
            }

            // Точки не едут за пальцем: компенсируем сдвиг карусели.
            pageControl(addNew: addNew)
                .offset(x: pin)
                .opacity(visible)
        }
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

    private var addServiceCard: some View {
        darkCard(symbol: "plus", title: "Добавить ТО")
    }

    private func darkCard(symbol: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.43)
                .foregroundStyle(.white)
        }
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

    /// Карточка «ТО через» с прогрессом (Figma 45867:3026).
    private var nextServiceCard: some View {
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
    private var historyCard: some View {
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
    private var deleteButton: some View {
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
