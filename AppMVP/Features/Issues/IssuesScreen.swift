import SwiftUI

/// Раздел «Ошибки» — Figma секция `46084:1942`.
///
/// Флоу целиком:
/// 1. история пуста → «Слушать» пишет **на месте**, без модалки;
/// 2. история есть → запись идёт в **модалке** поверх притемнённого экрана
///    (нода `46105:3970`): модалка нужна, чтобы закрыть уже непустой экран;
/// 3. «Стоп» → снизу выезжает шторка «Вот что мы нашли» (нода `46102:3369`);
/// 4. «Да, добавить ошибки» → находки уходят в историю и она появляется;
///    «Нет, не добавлять» → история не меняется.
struct IssuesScreen: View {
    /// Пока шторка находок открыта, таббар должен уйти: модалка накрывает
    /// экран целиком, а таббар рисуется в `CarMainView` поверх нас и
    /// закрывал нижнюю кнопку «Нет, не добавлять».
    @Binding var hidesTabBar: Bool

    @StateObject private var meter = AudioLevelMeter()

    /// История пуста на старте и растёт только после подтверждения находок.
    @State private var history: [IssueGroup] = []
    @State private var isRecording = false
    @State private var showFindings = false

    private var hasHistory: Bool { !history.isEmpty }

    /// Модалка только когда под ней есть что притемнять. На пустом экране она
    /// не нужна и мешает: закрывать нечего.
    private var isModalRecording: Bool { isRecording && hasHistory }

    /// Зазор от описания до кнопки: 206 пока истории нет (`46096:2555`)
    /// и 48, когда она появилась (`46105:4251`).
    private var buttonGap: CGFloat { hasHistory ? 48 : 206 }

    /// Верх блока: 62 + 16 у экрана с историей, 64.5 + 16 у пустого.
    private var blockTop: CGFloat { hasHistory ? 78 : 80.5 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            screen

            if isModalRecording {
                // Затемнение плотнее макетного: там панель лежит поверх такого
                // же блока и просвечивать нечему, а у нас под ней история.
                Figma.graysBlack.opacity(0.78)
                    .ignoresSafeArea()
                    .transition(.opacity)

                recordingPanel
                    .frame(width: 370, height: 549.289, alignment: .top)
                    .offset(x: 16, y: 65.076)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Figma.graysBlack)
        .animation(Motion.sheet, value: isRecording)
        .animation(Motion.sheet, value: history.count)
        .onDisappear { meter.stop() }
        .bottomSheet(isPresented: $showFindings) { findingsSheet }
        .onChange(of: showFindings) { _, shown in hidesTabBar = shown }
    }

    // MARK: - Экран

    private var screen: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heading
                Spacer(minLength: 0).frame(height: 48)
                // Пока истории нет, шар оживает прямо здесь: модалки не будет.
                SoundOrb(level: isRecording && !hasHistory ? meter.level : 0)
                Spacer(minLength: 0).frame(height: 24)
                caption
                Spacer(minLength: 0).frame(height: buttonGap)
                listenButton

                if hasHistory {
                    Spacer(minLength: 0).frame(height: 48)
                    historySection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, blockTop)
            .padding(.bottom, 140)
        }
        // Пока истории нет, прокручивать нечего — иначе экран оттягивается
        // в пустоту, как это было на странице «Добавить авто».
        .scrollDisabled(!hasHistory)
    }

    /// Модалка записи, нода `46105:4087`: карточка 370×549.289, внутри
    /// отступ 16, поэтому контент 338.
    private var recordingPanel: some View {
        VStack(spacing: 0) {
            heading
            Spacer(minLength: 0).frame(height: 48)
            SoundOrb(level: meter.level)
            Spacer(minLength: 0).frame(height: 24)
            caption
            Spacer(minLength: 0).frame(height: 48)
            listenButton
        }
        .padding(16)
        .background {
            // Плотнее, чем «Liquid Glass - Clear» в макете: сквозь него
            // читался текст экрана под панелью.
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color(white: 0.11))
                .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.6), radius: 40, y: 12)
        }
    }

    private var heading: some View {
        Text("Поднесите телефон \nк двигателю")
            .font(.system(size: 26, weight: .bold))
            .figmaLineHeight(31.2, fontSize: 26, weight: .bold)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    /// Переносы проставлены руками, как и у заголовка, и это не косметика.
    /// В макете описание занимает **три** строки и объявлено высотой 63; текст
    /// системным шрифтом укладывается в две, блок становится на 21pt короче, и
    /// на эти 21pt уезжает вверх всё, что ниже, — в первую очередь кнопка.
    private var caption: some View {
        Text("Поднесите телефон к двигателю или выхлопной\nтрубе и нажмите кнопку для начала\nдиагностики")
            .font(.system(size: 16))
            .tracking(-0.31)
            .figmaLineHeight(21, fontSize: 16)
            .foregroundStyle(Figma.vibrantSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    /// Аннотация макета к ноде `46105:4259`: «кнопка работает по принципу
    /// старт стоп».
    ///
    /// Стиль — Glass Prominent в светлом режиме, то есть **чёрная** пилюля со
    /// стеклом. Раньше стояла заливка `darkCard` (#1A1A1A) с обводкой, и она
    /// читалась серой.
    private var listenButton: some View {
        Button(action: toggleRecording) {
            Text(isRecording ? "Стоп" : "Слушать")
                .font(.system(size: 17))
                .tracking(-0.43)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .liquidGlass(in: Capsule(), tint: Figma.graysBlack) {
                    Capsule()
                        .fill(Figma.graysBlack)
                        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - История (нода 46090:2356)

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("История")
                .font(.system(size: 22, weight: .bold))
                .figmaLineHeight(28, fontSize: 22, weight: .bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0).frame(height: 20)

            statsCard

            ForEach(history) { group in
                Spacer(minLength: 0).frame(height: 24)

                Text(group.date)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.43)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(group.issues) { issue in
                    Spacer(minLength: 0).frame(height: 16)
                    darkIssueCard(issue)
                }
            }
        }
    }

    /// Карточка со счётчиками, нода `46093:2410`: 370×96, две половины.
    private var statsCard: some View {
        HStack(spacing: 0) {
            counter(title: "Прослушиваний", value: history.count)
            counter(title: "Неисправности", value: history.reduce(0) { $0 + $1.issues.count })
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .background(darkCardSurface)
    }

    private func counter(title: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.08)
                .foregroundStyle(Figma.vibrantSecondary)

            Text("\(value)")
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.45)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    /// Карточка неисправности на тёмном экране, нода `46093:2421`: 370×102.
    private func darkIssueCard(_ issue: EngineIssue) -> some View {
        issueBody(issue, title: .white, detail: Figma.vibrantSecondary)
            .background(darkCardSurface)
    }

    /// Скругление карточки. 26 было мало: по замеру рендера макета белое
    /// начинается в 15pt от края на 6px ниже верха карточки, в 6pt на 15px и в
    /// 2pt на 22px — это радиус около 34, у 26 выходило 9 / 3 / 1.
    static let cardRadius: CGFloat = 34

    private static let cardShape = RoundedRectangle(cornerRadius: cardRadius,
                                                    style: .continuous)

    private var darkCardSurface: some View {
        Self.cardShape
            .fill(Figma.darkCard)
            .overlay(Self.cardShape.stroke(Color.white.opacity(0.10), lineWidth: 0.5))
    }

    /// Заголовок здесь Subheadline/Emphasized (15pt), а не Body: с 17pt
    /// карточка вырастала до 104 вместо заявленных в макете 102. Описание
    /// ровно в две строки — в макете под него отведено 36pt, то есть 2 × 18.
    private func issueBody(_ issue: EngineIssue,
                           title: Color, detail: Color) -> some View {
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

    private var findingsSheet: some View {
        VStack(spacing: 0) {
            sheetToolbar
            findingsList
                .padding(.top, Findings.listTop)
        }
        .frame(height: Findings.height)
        .frame(maxWidth: .infinity)
        // Подложка сплошная, а не стекло. Лист на весь экран в iOS
        // непрозрачный, и это видно замером: сквозь `glassEffect` светил шар,
        // и фон шторки уходил в зелень — rgb(245,253,251) там, где в макете
        // нейтральные 243.
        .background(Self.sheetShape.fill(Figma.backgroundsPrimary))
        .environment(\.colorScheme, .light)
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
                                    .init(color: Figma.backgroundsPrimary.opacity(0), location: 0),
                                    .init(color: Figma.backgroundsPrimary.opacity(0.9), location: 0.55),
                                    .init(color: Figma.backgroundsPrimary, location: 0.68)
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
                ForEach(IssuesStub.findings) { issue in
                    issueBody(issue, title: Figma.labelsPrimary,
                              detail: Figma.vibrantSecondary)
                        .background(lightCardSurface)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// Карточки в макете держатся тенью, а не заливкой: их белое 255 против
    /// фона шторки 252 — разница в три уровня. Всю работу делает тень,
    /// проседающая до 245 у края карточки и до 243 в зазоре между двумя.
    private var lightCardSurface: some View {
        Self.cardShape
            .fill(Figma.backgroundsPrimary)
            .shadow(color: .black.opacity(0.10), radius: 10, y: 2)
    }

    private var findingsButtons: some View {
        VStack(spacing: 12) {
            GlassProminentButton(title: "Да, добавить ошибки", action: approveFindings)
            GlassButton(title: "Нет, не добавлять") { showFindings = false }
        }
        .padding(.horizontal, 16)
    }

    /// Тулбар: крестик слева, заголовок по центру, чёрная галочка справа.
    private var sheetToolbar: some View {
        ZStack {
            Text("Вот что мы нашли")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.43)
                .foregroundStyle(Figma.labelsPrimary)

            HStack {
                Button { showFindings = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Figma.vibrantSecondary)
                        .frame(width: 44, height: 44)
                        // Кружок под крестиком в макете есть — Button Group со
                        // стеклом без prominent. Подача та же, что у крестика
                        // остальных шторок проекта.
                        .liquidGlass(in: Circle()) {
                            Circle()
                                .fill(.white)
                                .overlay(Circle().stroke(Color(white: 232 / 255), lineWidth: 0.5))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть")

                Spacer(minLength: 0)

                Button(action: approveFindings) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Figma.graysBlack))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Добавить ошибки")
            }
        }
        .frame(height: Findings.toolbarHeight)
        .padding(.horizontal, 16)
        .padding(.top, Findings.toolbarTop)
    }

    // MARK: - Действия

    private func toggleRecording() {
        if isRecording {
            meter.stop()
            isRecording = false
            // Останавливаем — и сразу показываем, что нашли. История сама по
            // себе не появляется: её наполняет только подтверждение.
            showFindings = true
        } else {
            isRecording = true
            meter.start()
        }
    }

    private func approveFindings() {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        history.append(IssueGroup(date: formatter.string(from: .now),
                                  issues: IssuesStub.findings))
        showFindings = false
    }
}

// MARK: - Данные

struct EngineIssue: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

struct IssueGroup: Identifiable {
    let id = UUID()
    let date: String
    let issues: [EngineIssue]
}

/// Заглушка. Настоящего разбора звука двигателя нет: он требует модели на
/// сервере и размеченных записей. Держим отдельно, чтобы выкинуть одним
/// куском, — так же как `StubVehicleLookup`.
enum IssuesStub {
    /// Шесть находок — столько карточек в шторке макета (`46102:3369`): шесть
    /// по 102 плюс пять отступов по 16 как раз дают её 692. В самом макете все
    /// шесть с одинаковым текстом, то есть это наполнитель; здесь они разные,
    /// чтобы список не выглядел сломанным повтором.
    static let findings: [EngineIssue] = [
        EngineIssue(title: "Проблемы с трансмиссией",
                    detail: "Проблемы с переключением передач, слышен скрежещущий звук"),
        EngineIssue(title: "Проверка системы охлаждения",
                    detail: "Температура двигателя выше нормы, возможны утечки"),
        EngineIssue(title: "Стук в подвеске",
                    detail: "На неровностях слышен стук спереди, возможен износ стоек"),
        EngineIssue(title: "Свист ремня привода",
                    detail: "Свист на холодном пуске, ремень навесного оборудования"),
        EngineIssue(title: "Неровный холостой ход",
                    detail: "Обороты плавают на прогретом двигателе, возможен подсос воздуха"),
        EngineIssue(title: "Шум подшипника",
                    detail: "Гул нарастает с оборотами, похоже на подшипник помпы")
    ]
}
