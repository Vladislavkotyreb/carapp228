import SwiftData
import SwiftUI

/// Заголовок здесь Subheadline/Emphasized (15pt), а не Body: с 17pt
/// карточка вырастала до 104 вместо заявленных в макете 102. Описание
/// ровно в две строки — в макете под него отведено 36pt, то есть 2 × 18.
/// Тёмная карточка на экране прибита к ноде макета `46093:2421` — 370×102.
/// Совет по расходникам здесь больше не живёт: с 26.09.2026 он — лента
/// «Что можно купить» в шторке находок (`FindingsSheet.findingCard`).
struct IssueCardBody: View {
    let issue: EngineIssue
    let title: Color
    let detail: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(issue.title)
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.23)
                .figmaLineHeight(20, fontSize: 15, weight: .semibold)
                .foregroundStyle(title)

            Text(issue.detail)
                .font(.system(size: 13))
                .tracking(-0.08)
                .figmaLineHeight(18, fontSize: 13)
                .lineLimit(2)
                .foregroundStyle(detail)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        // Высота карточки объявлена в макете: 102. Сложением строк она не
        // получается — системные метрики SF дают 100.7, и на шестой карточке
        // список уезжает вверх на 6pt. Добор идёт снизу, поэтому текст
        // остаётся ровно там, где в макете.
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
    }
}

/// Шторка «Вот что мы нашли» (нода `46102:3369`) — вынесена из `IssuesScreen`
/// 25.09.2026, чтобы тот же флоу открывался и с главной.
///
/// 26.09.2026 переделана по просьбе пользователя: сверху вопрос «Прикрепить
/// к машине?», включённый открывает карусель машин — на какой прокрутка
/// остановилась, та и выбрана. Находка — название, «что это может быть» и
/// лента того, что можно купить. Тулбар, кнопки и геометрия шторки — прежние.
struct FindingsSheet: View {
    /// Машина для карусели — значения, а не модель: шторке не нужна база,
    /// а переходник `Car → CarChoice` лежит ниже, во вью-слое.
    struct CarChoice: Identifiable {
        let id: PersistentIdentifier
        let name: String
        /// Номер, уже разбитый на группы. Пустой — машина без номера.
        let plate: String
        let photo: Data?
        let catalogSlug: String?
    }

    let findings: [EngineIssue]
    /// Разбор не услышал мотора — шторка в пустом состоянии.
    let nothingHeard: Diagnosis.HeardKind?
    /// Машины пользователя. Пусто — вопроса о прикреплении нет вовсе.
    let cars: [CarChoice]
    let onClose: () -> Void
    /// Сохранить находки. `nil` — не прикреплять ни к одной машине.
    let onApprove: (PersistentIdentifier?) -> Void
    /// «Записать ещё раз» из пустого состояния.
    let onRetry: () -> Void

    /// Прикреплять ли к машине. Включено сразу, когда слушали с экрана машины:
    /// там вопрос уже решён тем, откуда нажали «Послушать».
    @State private var attach: Bool
    /// Машина, на которой остановилась карусель. Пишется прокруткой
    /// (`scrollPosition`) только при смене карточки, не на каждом кадре.
    @State private var selectedCar: PersistentIdentifier?
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(findings: [EngineIssue], nothingHeard: Diagnosis.HeardKind?,
         cars: [CarChoice], preselected: PersistentIdentifier?, attachByDefault: Bool,
         onClose: @escaping () -> Void,
         onApprove: @escaping (PersistentIdentifier?) -> Void,
         onRetry: @escaping () -> Void) {
        self.findings = findings
        self.nothingHeard = nothingHeard
        self.cars = cars
        self.onClose = onClose
        self.onApprove = onApprove
        self.onRetry = onRetry
        _attach = State(initialValue: attachByDefault && !cars.isEmpty)
        let start = cars.first { $0.id == preselected }?.id ?? cars.first?.id
        _selectedCar = State(initialValue: start)
    }

    private func approve() {
        onApprove(attach ? selectedCar : nil)
    }

    private var selectedChoice: CarChoice? {
        guard attach else { return nil }
        return cars.first { $0.id == selectedCar }
    }

    /// Скругление карточки находки — то же 34, что у тёмной карточки экрана.
    private static let cardShape = RoundedRectangle(cornerRadius: 34, style: .continuous)

    // MARK: - Шторка «Вот что мы нашли» (нода 46102:3369)

    /// Форма и подача как у остальных шторок проекта — образец
    /// `AddServiceChoiceSheet`. Своя версия была голым `VStack` без контейнера:
    /// без формы, без белой заливки, без грабера и с растягивающимся
    /// `Spacer`, из-за которого кнопки уезжали за нижний край экрана.
    private static let sheetShape = UnevenRoundedRectangle(
        topLeadingRadius: 34, bottomLeadingRadius: 58,
        bottomTrailingRadius: 58, topTrailingRadius: 34
    )

    /// Геометрия шторки из ноды `46102:3369`. Вынесена в константы, потому что
    /// два числа связаны: под последней карточкой оставляется ровно блок
    /// кнопок, иначе она навсегда остаётся под ними.
    private enum Findings {
        /// Шторка занимает 812 из 874
        static let height: CGFloat = 812
        /// Тулбар: отступ сверху 16, высота 54
        static let toolbarTop: CGFloat = 16
        static let toolbarHeight: CGFloat = 54
        /// Список начинается на 86 от верха шторки, то есть через 16 после тулбара
        static let listTop: CGFloat = 16
        /// Кнопки: 54 + 12 + 54 и 22 до низа шторки — итого 142
        static let buttonsBlock: CGFloat = 142
        static let buttonsBottom: CGFloat = 22
        /// Высота растворения контента к низу. По рендеру макета оно начинается
        /// примерно на 708 и заканчивается на 804 при низе шторки 874.
        static let fadeHeight: CGFloat = 166
    }

    /// Геометрия новых блоков 26.09.2026. Контейнер «Прикрепить» сверен с
    /// макетом пользователя; остальное подобрано на экране 390 pt.
    private enum Layout {
        /// Вопрос и карусель — один контейнер (макет пользователя 26.09.2026,
        /// Figma `46312:20`): поля 12, между строкой и подложкой 12.
        static let attachPadding: CGFloat = 12
        static let attachGap: CGFloat = 12
        /// Подложка внутри контейнера, радиус 12. Поля ленты: в макете машина
        /// 274 в подложке 346, то есть по 36 с краёв.
        static let carMargin: CGFloat = 36
        static let carSpacing: CGFloat = 12
        static let carPhotoHeight: CGFloat = 124
        static let carPanelRadius: CGFloat = 12
        static let carPanelPadding: CGFloat = 16
        static let rowRadius: CGFloat = 24
        /// Карточка расходника: две строки названия и «Найти». 156, а не
        /// 136: «трансмиссионное» в 13 semibold не влезало в строку.
        static let itemWidth: CGFloat = 156
        static let itemRadius: CGFloat = 20
        static let iconSize: CGFloat = 32
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Контент уходит под тулбар, тот стоит на размытии с градиентом
            // — HIG, эталон пользователя; сплошная заливка верха — косяк,
            // который уже ловили на главном экране.
            VStack(spacing: 0) {
                if let heard = nothingHeard {
                    nothingHeardState(heard)
                } else {
                    findingsList
                }
            }
            .padding(.top, Findings.toolbarTop + Findings.toolbarHeight
                     + Findings.listTop)

            sheetToolbar
                .background {
                    SheetTopBlur(tint: Figma.sheetBackground)
                        .frame(height: 118)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
        }
        .frame(height: Findings.height)
        .frame(maxWidth: .infinity)
        // Подложка сплошная, а не стекло. Лист на весь экран в iOS
        // непрозрачный, и это видно замером: сквозь `glassEffect` светил шар,
        // и фон шторки уходил в зелень. С тёмной темой поверхность стала
        // Backgrounds (Grouped)/Secondary — как у остальных шторок.
        .background(Self.sheetShape.fill(Figma.sheetBackground))
        // Без склейки в один слой `shadow` достаётся **каждому** примитиву
        // внутри по отдельности: свою тень получала каждая карточка и каждая
        // строка текста, и фон шторки уходил с 255 до 236. Раньше это гасило
        // стекло — `glassEffect` сам делает слой, — а со сплошной подложкой
        // склеивать надо руками.
        .compositingGroup()
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .overlay(alignment: .top) {
            Capsule()
                .fill(Figma.grabber)
                .frame(width: 58, height: 4)
                .padding(.top, 5)
        }
    }

    /// Разбор не нашёл мотора. Показываем **что услышали вместо него** и одну
    /// кнопку: подтверждать нечего, а «Нет, не добавлять» рядом с пустым
    /// списком читается как выбор там, где выбора нет.
    private func nothingHeardState(_ heard: Diagnosis.HeardKind) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(systemName: "waveform.badge.exclamationmark")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Figma.vibrantSecondary)

            Spacer(minLength: 0).frame(height: 20)

            Text("Двигателя не слышно")
                .font(.system(size: 22, weight: .bold))
                .figmaLineHeight(28, fontSize: 22, weight: .bold)
                .foregroundStyle(Figma.labelsPrimary)

            Spacer(minLength: 0).frame(height: 8)

            Text(heard.explanation)
                .font(.system(size: 15))
                .figmaLineHeight(20, fontSize: 15)
                .foregroundStyle(Figma.vibrantSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            Spacer(minLength: 0)

            GlassProminentButton(title: "Записать ещё раз") {
                onRetry()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, Findings.buttonsBottom)
        }
        .frame(maxWidth: .infinity)
    }

    /// Список находок с кнопками внизу.
    ///
    /// На iOS 26 кнопки объявляются панелью безопасной зоны, и система сама
    /// делает две вещи: считает отступ под них и размывает край прокрутки под
    /// панелью. Именно это размытие в макете гасит шестую карточку до 229 —
    /// нарисованным поверх градиентом такое получается только приблизительно,
    /// а системе это штатное поведение.
    @ViewBuilder
    private var findingsList: some View {
        if #available(iOS 26.0, *) {
            findingsScroll
                .safeAreaBar(edge: .bottom) {
                    findingsButtons.padding(.bottom, Findings.buttonsBottom)
                }
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            // На iOS 17–25 системного эффекта края нет: рисуем градиент сами.
            // Профиль снят с рендера макета — прозрачный к 708, почти сплошной
            // к 792, сплошной к 804 (в координатах экрана 402×874).
            findingsScroll
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    findingsButtons
                        .padding(.bottom, Findings.buttonsBottom)
                        .padding(.top, Findings.fadeHeight - Findings.buttonsBlock)
                        .background {
                            LinearGradient(
                                stops: [
                                    .init(color: Figma.sheetBackground.opacity(0), location: 0),
                                    .init(color: Figma.sheetBackground.opacity(0.9), location: 0.55),
                                    .init(color: Figma.sheetBackground, location: 0.68)
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                            .ignoresSafeArea()
                        }
                }
        }
    }

    private var findingsScroll: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if !cars.isEmpty {
                    attachSection
                }
                ForEach(findings) { issue in
                    findingCard(issue)
                }
            }
        }
    }

    // MARK: - Прикрепить к машине

    /// Вопрос-переключатель и под ним, когда включён, карусель машин.
    /// Один контейнер на вопрос и выбор (макет пользователя, блок `46312:20`
    /// в Figma, правка 26.09.2026): строка «иконка — вопрос — переключатель»,
    /// а под ней, когда включено, чёрная подложка с машинами. Включили —
    /// контейнер дорастает вниз, подложка проявляется изнутри него: клип по
    /// форме контейнера прячет её, пока высота растёт. Подписи под вопросом
    /// больше нет — выбранную машину и так видно.
    private var attachSection: some View {
        VStack(spacing: Layout.attachGap) {
            HStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Figma.labelsPrimary)
                    .frame(width: Layout.iconSize + 4, height: Layout.iconSize + 4)
                    .background(Circle().fill(Figma.fillsTertiary))

                Text("Прикрепить к\u{00A0}машине?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Figma.labelsPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("Прикрепить к машине", isOn: $attach.animation(revealAnimation))
                    .labelsHidden()
                    .tint(Figma.accentsGreen)
            }

            if attach {
                carCarousel
                    .transition(reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                            removal: .opacity))
            }
        }
        .padding(Layout.attachPadding)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Layout.rowRadius, style: .continuous)
            .fill(Figma.fillsTertiary))
        .clipShape(RoundedRectangle(cornerRadius: Layout.rowRadius, style: .continuous))
        .padding(.horizontal, 16)
    }

    /// Рост контейнера и проявление подложки. Плавная кривая без отскока:
    /// пружина с отскоком дёргала бы список находок под контейнером.
    private var revealAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.38)
    }

    /// Карусель машин. Выбор — там, где прокрутка остановилась: `viewAligned`
    /// докручивает до карточки, `scrollPosition` отдаёт её id. Масштаб и
    /// прозрачность соседей считает `scrollTransition` — позиция прокрутки
    /// в состояние вью не попадает (docs/TRAPS.md, съеденный скролл).
    private var carCarousel: some View {
        VStack(spacing: 12) {
            carScroll
            // Точки — единственный явный знак, что машин несколько: соседи
            // у краёв подложки видны чёрным полем своего кадра, не машиной.
            if cars.count > 1 {
                HStack(spacing: 6) {
                    ForEach(cars) { choice in
                        Circle()
                            .fill(choice.id == selectedCar ? Figma.labelsPrimary : Figma.labelsTertiary)
                            .frame(width: 6, height: 6)
                    }
                }
                .animation(Motion.selection, value: selectedCar)
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Layout.carPanelPadding)
        // Подложка чёрная, как фон главной: кадры каталога студийные на
        // чёрном и сливаются с ней — машины стоят без рамок.
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: Layout.carPanelRadius, style: .continuous))
    }

    private var carScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Layout.carSpacing) {
                ForEach(cars) { choice in
                    CarChoiceItem(choice: choice, isSelected: choice.id == selectedCar,
                                  photoHeight: Layout.carPhotoHeight)
                        .containerRelativeFrame(.horizontal)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.86)
                                .opacity(phase.isIdentity ? 1 : 0.4)
                        }
                        .onTapGesture {
                            withAnimation(Motion.selection) { selectedCar = choice.id }
                        }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, Layout.carMargin, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        // Без `anchor: .center`: вместе с полями он ставил карточку на
        // половину ширины за вычетом полей — первая уезжала вправо на 67 pt
        // (кадр 26.09). `viewAligned` и так держит её у поля, поля симметричны.
        .scrollPosition(id: $selectedCar)
        .sensoryFeedback(.selection, trigger: selectedCar)
    }

    // MARK: - Находка

    /// Находка: название, что это может быть, что можно купить. У вердикта
    /// и у сообщений об ошибке кода детали нет — остаются название и подпись.
    private func findingCard(_ issue: EngineIssue) -> some View {
        let items = issue.part.map(PartAdvice.parts) ?? []
        return VStack(alignment: .leading, spacing: 0) {
            Text(issue.title)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.43)
                .foregroundStyle(Figma.labelsPrimary)
                .padding(.horizontal, 20)

            Text(issue.detail)
                .font(.system(size: 13))
                .tracking(-0.08)
                .figmaLineHeight(18, fontSize: 13)
                .foregroundStyle(Figma.graysGray)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .padding(.horizontal, 20)

            if let meaning = issue.part.flatMap(PartAdvice.meaning) {
                sectionLabel("Что это может быть")
                Text(meaning)
                    .font(.system(size: 15))
                    .tracking(-0.23)
                    .figmaLineHeight(20, fontSize: 15)
                    .foregroundStyle(Figma.labelsPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            if !items.isEmpty {
                sectionLabel("Что можно купить")
                // Лента во всю ширину карточки: первая карточка на поле
                // текста, последняя уходит под край — видно, что листается.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items, id: \.self) { item in
                            buyCard(item)
                        }
                    }
                }
                .contentMargins(.horizontal, 20, for: .scrollContent)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardSurface)
        .padding(.horizontal, 16)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Figma.labelsSecondary)
            .padding(.top, 16)
            .padding(.bottom, 6)
            .padding(.horizontal, 20)
    }

    /// Карточка расходника. «Найти» — поиск в Яндекс Маркете, с названием
    /// машины, если результаты прикреплены к ней. Номер в запрос не идёт.
    private func buyCard(_ item: String) -> some View {
        Button {
            if let url = PartAdvice.searchURL(item: item, carName: selectedChoice?.name) {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: PartAdvice.symbol(forItem: item))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Figma.accentsYellow)
                    .frame(width: Layout.iconSize, height: Layout.iconSize)
                    .background(Circle().fill(Figma.fillsTertiary))

                Text(item)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.08)
                    .figmaLineHeight(18, fontSize: 13, weight: .semibold)
                    .foregroundStyle(Figma.labelsPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    Text("Найти")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 13))
                .foregroundStyle(Figma.graysGray)
            }
            .padding(12)
            .frame(width: Layout.itemWidth, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Layout.itemRadius, style: .continuous)
                .fill(Figma.fillsTertiary))
            .contentShape(RoundedRectangle(cornerRadius: Layout.itemRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item) — найти в\u{00A0}Яндекс Маркете")
    }

    /// Карточка находки на тёмной шторке. Светлую держала тень, тёмную
    /// держит заливка: Fills/Tertiary над #1C1C1E даёт ту же разницу
    /// в несколько уровней, что была у белого 255 на 252.
    private var cardSurface: some View {
        Color.clear
            .background(Self.cardShape.fill(Figma.fillsTertiary))
            .shadow(color: .black.opacity(0.10), radius: 10, y: 2)
    }

    private var findingsButtons: some View {
        VStack(spacing: 12) {
            GlassProminentButton(title: "Да, добавить ошибки", action: approve)
            GlassButton(title: "Нет, не добавлять", action: onClose)
        }
        .padding(.horizontal, 16)
    }

    /// Тулбар: крестик слева, заголовок по центру, чёрная галочка справа.
    private var sheetToolbar: some View {
        ZStack {
            // В пустом состоянии «нашли» — неправда: не нашли ничего.
            Text(nothingHeard == nil ? "Вот что мы нашли" : "Запись")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.43)
                .foregroundStyle(Figma.labelsPrimary)

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        // Кружок под крестиком в макете есть — Button Group со
                        // стеклом без prominent. Подача та же, что у крестика
                        // остальных шторок проекта.
                        .liquidGlass(in: Circle(), tint: Figma.sheetControl) {
                            Circle()
                                .fill(Figma.sheetControl)
                                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                        }
                .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть")

                Spacer(minLength: 0)

                if nothingHeard == nil {
                    // Белая галочка-акцент, как у остальных шторок.
                    Button(action: approve) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Figma.labelsPrimary))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Добавить ошибки")
                }
            }
        }
        .frame(height: Findings.toolbarHeight)
        .padding(.horizontal, 16)
        .padding(.top, Findings.toolbarTop)
    }
}

/// Машина в карусели шторки находок: кадр, название, номер — без карточки,
/// прямо на чёрной подложке. Выбранную выделяет не рамка, а сама карусель:
/// соседи уменьшены и приглушены (`scrollTransition`).
///
/// Шрифтовая пара — узкий SF Pro, как у номера и подписей на главной:
/// название Bold, номер Medium (правка пользователя 26.09.2026).
private struct CarChoiceItem: View {
    let choice: FindingsSheet.CarChoice
    let isSelected: Bool
    let photoHeight: CGFloat

    @State private var image: UIImage?
    @State private var isCatalog = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let image {
                    if isCatalog {
                        // Кадр каталога студийный, на чёрном: целиком, не обрезая.
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        // Своё фото — не прямоугольник-карточка, а растворённое
                        // к краям пятно: иначе рамка вернулась бы через кадр.
                        Image(uiImage: image).resizable().scaledToFill()
                            .mask(RadialGradient(colors: [.black, .black, .clear],
                                                 center: .center, startRadius: 0,
                                                 endRadius: photoHeight * 1.1))
                    }
                } else {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Figma.labelsTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: photoHeight)
            .clipped()
            .allowsHitTesting(false)

            VStack(spacing: 2) {
                Text(choice.name)
                    .font(.system(size: 20, weight: .bold).width(.condensed))
                    .foregroundStyle(Figma.labelsPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(choice.plate.isEmpty ? "Без номера" : choice.plate)
                    .font(.system(size: 15, weight: .medium).width(.condensed))
                    .tracking(0.4)
                    .foregroundStyle(Figma.graysGray)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .task(id: choice.id) { await load() }
    }

    private func load() async {
        if let data = choice.photo, let decoded = await ImageLoader.decode([data]).first {
            image = decoded
            isCatalog = false
        } else if let slug = choice.catalogSlug,
                  let url = Bundle.main.url(forResource: slug, withExtension: "heic",
                                            subdirectory: "CarCatalog") {
            image = UIImage(contentsOfFile: url.path)
            isCatalog = true
        }
    }
}

extension FindingsSheet.CarChoice {
    /// Переходник из модели — во вью-слое, как требует `Core/Pure`.
    init(_ car: Car) {
        self.init(id: car.persistentModelID,
                  name: car.name,
                  plate: car.plate.isEmpty ? "" : PlateFormat.format(car.plate),
                  photo: car.photo,
                  catalogSlug: CarCatalog.slug(name: car.name, generation: car.generation,
                                               plate: car.plate))
    }
}

/// Разбор записи в карточки находок — общий для «Ошибок» и быстрого
/// прослушивания с главной. Вынесен из `IssuesScreen` 25.09.2026 без правок
/// логики: пороги и формулировки ниже прошли разбор с пользователем.
enum DiagnosisCards {
    /// Итог разбора: карточки или пустое состояние «мотора не слышно».
    struct Outcome {
        var cards: [EngineIssue]
        var nothingHeard: Diagnosis.HeardKind?
    }

    /// Можно ли разбирать по-настоящему. Нет — работаем на заглушке, как
    /// «Карта» без ключа.
    static var canDiagnose: Bool { LocalDiagnosis.isAvailable || DiagnosisEndpoint.isConfigured }

    /// Разбор записи целиком: локальная модель, сервер запасным путём,
    /// ошибка — карточкой. Без записи или без моделей — заглушка.
    static func run(recording: URL?) async -> Outcome {
        #if DEBUG
        // Съёмка состояний: микрофон симулятора слышит тишину, и разбор
        // честно отвечает «ничего тревожного» — находок с деталями не увидеть.
        // `SIMCTL_CHILD_BEEPY_STUB_DIAGNOSIS=1 xcrun simctl launch …`
        if ProcessInfo.processInfo.environment["BEEPY_STUB_DIAGNOSIS"] == "1" {
            return Outcome(cards: IssuesStub.findings, nothingHeard: nil)
        }
        #endif
        guard canDiagnose, let recording else {
            return Outcome(cards: IssuesStub.findings, nothingHeard: nil)
        }
        do {
            // Локальный разбор первым: модели лежат в бандле, сеть не
            // нужна вовсе. Сервер остаётся отладочным запасным путём на
            // случай сборки без моделей.
            let diagnosis = LocalDiagnosis.isAvailable
                ? try await LocalDiagnosis.diagnose(fileURL: recording)
                : try await CarDiagnosisClient.diagnose(fileURL: recording)
            var heard: Diagnosis.HeardKind?
            let cards = issues(from: diagnosis, nothingHeard: &heard)
            return Outcome(cards: cards, nothingHeard: heard)
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription
                ?? "Не удалось разобрать запись"
            return Outcome(cards: [EngineIssue(title: "Не удалось разобрать запись", detail: reason)],
                           nothingHeard: nil)
        }
    }

    /// Разбор в карточки экрана.
    ///
    /// Здесь важно не смешать два **разных** числа, которые присылает сервер.
    ///
    /// `fault_probability` — отдельная голова «есть ли вообще неисправность».
    /// Она откалибрована температурой 3.08, то есть её сырую самоуверенность
    /// специально погасили, и заявленная ошибка калибровки ≈ 0.04. Этому числу
    /// можно верить как вероятности, и оно идёт первой карточкой.
    ///
    /// `causes[].p` — это **распределение по 21 семейству**, сумма по всем
    /// единица. Температура у этой головы 1.0, то есть не калибрована вовсе.
    /// Её 99 % значат «из версий модель почти всё веса отдала этой», а вовсе не
    /// «деталь сломана с вероятностью 99 %». Поэтому в подписи стоит «модель
    /// ставит сюда», а не «уверенность»: на демо-клипе как раз выходило
    /// 99 % на выхлоп при 64 % на сам факт неисправности.
    static func issues(from diagnosis: Diagnosis,
                       nothingHeard: inout Diagnosis.HeardKind?) -> [EngineIssue] {
        guard diagnosis.modelLoaded else {
            return [EngineIssue(title: "Модель не загружена",
                                detail: "Сервер запущен без модели — запустите его "
                                        + "с ключом --model models")]
        }

        // Первый и главный предохранитель: похоже ли это вообще на мотор.
        // Модель cardiag такого вопроса не задаёт — её головы различают
        // неисправный мотор и исправный, а варианта «это не машина» у них нет.
        // Отсюда и брался «дифференциал» в тихой комнате.
        guard diagnosis.isEngine else {
            // Не карточка в общем списке: шторка целиком переходит в пустое
            // состояние. Карточка соседствовала бы с кнопками «Да, добавить
            // ошибки» — предложением добавить в историю то, чего нет.
            nothingHeard = diagnosis.heard
            return []
        }

        // Версии показываем **только** когда голова «есть ли поломка» сказала
        // «да». Она единственная здесь откалибрована, и она же единственная,
        // что умеет ответить «нет»: у головы причин класса «ничего» нет, она
        // раскладывает свои 100 % по деталям при любом входе.
        //
        // Именно на этом ловилась тишина: запись без мотора, но с парой
        // шорохов даёт два «механических» куска, вердикт при этом честный
        // «норма, 32 %», а список деталей всё равно уверенно называл выхлоп
        // на 86 %. Гейт по вердикту это снимает.
        guard diagnosis.verdict == "fault" else { return [verdictCard(diagnosis)] }

        var cards = [verdictCard(diagnosis)]

        // Хвост ранжирования — шум: модель отдаёт распределение целиком, и
        // после уверенного первого места идут доли процента. Ниже 5 % не
        // показываем: такая карточка читается как найденная неисправность.
        let ranked = diagnosis.causes.filter { $0.part != "none" && $0.p >= 0.05 }

        cards += ranked.prefix(5).map { cause in
            let part = DiagnosisVocabulary.part(cause.part)
            let zone = DiagnosisVocabulary.zone(forPart: cause.part)
            // У части семейств название совпадает с зоной («Выпускная система»),
            // и подпись выходила повтором.
            let where_ = zone == part ? "" : zone + " · "
            return EngineIssue(title: part,
                               detail: where_ + "модель ставит сюда " + percent(cause.p),
                               advice: PartAdvice.line(cause.part),
                               part: cause.part)
        }

        if ranked.isEmpty {
            cards.append(EngineIssue(
                title: "Конкретную деталь назвать нельзя",
                detail: "Ни одна версия не набрала веса — звука для этого мало"))
        }
        return cards
    }

    /// Первая карточка: то единственное число, которое здесь означает
    /// вероятность в обычном смысле слова.
    ///
    /// Про сегменты здесь только оговорка, а не запрет. Жёсткий запрет тут
    /// стоял и оказался вреден: порог громкости в каскаде относительный, и
    /// ровно урчащий мотор кусков не даёт так же, как тишина. Отсеивать не мотор
    /// должен привратник, а это его работа, не наша.
    static func verdictCard(_ diagnosis: Diagnosis) -> EngineIssue {
        let share = percent(diagnosis.faultProbability)
        let caveat = diagnosis.segmentCount == 0
            ? " Чистого куска звука выделить не удалось, разбор по всей записи."
            : ""

        switch diagnosis.verdict {
        case "fault":
            return EngineIssue(title: "Похоже на неисправность",
                               detail: "Оценка «что-то не так» — \(share). "
                                       + "Ниже версии, что именно, по убыванию." + caveat)
        case "normal":
            return EngineIssue(title: "Ничего тревожного не слышно",
                               detail: "Оценка «что-то не так» — \(share)." + caveat)
        default:
            return EngineIssue(title: "По этой записи не берусь судить",
                               detail: "Оценка «что-то не так» — \(share), "
                                       + "это слишком близко к середине." + caveat)
        }
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))\u{00A0}%"
    }
}

extension EngineCheck {
    /// Подтверждённые находки уходят в базу — к машине и с её пробегом.
    /// Порядок сохраняется номером: разбор ранжированный, а связь SwiftData
    /// порядок не гарантирует. Общий для «Ошибок» и быстрого прослушивания,
    /// чтобы два пути не разошлись в том, что именно пишется.
    @discardableResult
    static func record(_ issues: [EngineIssue], car: Car?, in context: ModelContext) -> EngineCheck {
        let check = EngineCheck(car: car, mileage: car?.odometer)
        context.insert(check)
        for (index, issue) in issues.enumerated() {
            let finding = EngineFinding(title: issue.title, detail: issue.detail,
                                        advice: issue.advice, order: index)
            finding.check = check
            context.insert(finding)
        }
        return check
    }
}
