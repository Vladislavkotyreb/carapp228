import SwiftData
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

    /// История прослушиваний из базы. Свежие сверху — так же, как записи ТО.
    /// Раньше жила в `@State` и исчезала при перезапуске приложения.
    @Query(sort: \EngineCheck.date, order: .reverse) private var history: [EngineCheck]
    @Environment(\.modelContext) private var modelContext

    /// Что раздел сейчас делает. Одно значение вместо `isRecording`
    /// и `isAnalyzing`: «записываю и разбираю одновременно» больше нельзя
    /// выразить. Читатели ниже вычисляются отсюда и остались прежними.
    @State private var activity: IssuesActivity = .idle

    @State private var showFindings = false
    /// Разбор не дал находок: мотора не слышно. Отдельным состоянием, потому
    /// что шторка в нём выглядит иначе — подтверждать нечего.
    @State private var nothingHeard: Diagnosis.HeardKind?

    /// Что показывает шторка. Пока сервер разбора не настроен — заглушка,
    /// после разбора — то, что вернул `cardiag`.
    @State private var findings: [EngineIssue] = IssuesStub.findings
    /// Хранится, чтобы отменить разбор при уходе с экрана: ответ приходит
    /// секундами позже, и без отмены он открывает шторку поверх другого раздела.
    @State private var analysisTask: Task<Void, Never>?

    private var hasHistory: Bool { !history.isEmpty }

    private var isRecording: Bool { activity == .recording }
    /// Запись отдана на разбор и ответа ещё нет.
    private var isAnalyzing: Bool { activity == .analyzing }

    /// Фаза экрана целиком — она же имя кадра в галерее состояний.
    /// Выводится в `IssuesPhase.of`, там же и проверяется.
    private var phase: IssuesPhase { .of(activity: activity, hasHistory: hasHistory) }

    /// Модалка только когда под ней есть что притемнять. На пустом экране она
    /// не нужна и мешает: закрывать нечего.
    private var isModalRecording: Bool { phase == .recordingModal }

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
        // Возврат в покой обязателен. Раньше его не было: отменённый разбор
        // выходит по `guard !Task.isCancelled` мимо сброса флага, и кнопка
        // оставалась навсегда отключённой с индикатором. Прерванная запись
        // залипала так же — «Стоп» на остановленном метре.
        .onDisappear { meter.stop(); analysisTask?.cancel(); activity = .idle }
        .bottomSheet(isPresented: $showFindings) { findingsSheet }
        // Таббар уходит под **любую** модалку раздела, а не только под шторку
        // находок. Панель записи затемняет экран целиком, и оставлять поверх
        // неё живой таббар неверно: модальное окно на то и модальное, что
        // забирает управление себе.
        .onChange(of: showFindings) { _, _ in syncTabBar() }
        .onChange(of: isModalRecording) { _, _ in syncTabBar() }
        // `onChange` молчит, если состояние истинно уже на входе в раздел, —
        // на этом ловилось скрытие таббара. Досылаем при появлении.
        .onAppear { syncTabBar() }
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
                caption(Self.screenCaption)
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
            caption(Self.panelCaption)
            Spacer(minLength: 0).frame(height: 48)
            listenButton
        }
        .padding(16)
        .background {
            // Заливка снята с рендера ноды `46105:4088` пипеткой: ровный
            // rgb(25,25,25) по всей панели, сверху донизу. Светлой кромки в
            // макете нет вовсе — стояла обводка 0.14, её убрал.
            // Тень остаётся: на затемнённом экране она отделяет панель от фона.
            Self.panelShape
                .fill(Figma.recordingPanel)
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
    /// Переносы у экрана и у модалки **разные**: блок там 370 и 338 точек.
    /// Одна строка на оба места разъезжается — в узкой панели она ломалась
    /// на четыре строки вместо трёх.
    private static let screenCaption =
        "Поднесите телефон к двигателю или выхлопной\nтрубе и нажмите кнопку для начала\nдиагностики"
    private static let panelCaption =
        "Поднесите телефон к двигателю или\nвыхлопной трубе и нажмите кнопку для\nначала диагностики"

    private func caption(_ text: String) -> some View {
        Text(text)
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
                // Индикатор оверлеем поверх скрытого лейбла — тот же приём,
                // что у `GlassProminentButton`: геометрия кнопки не должна
                // меняться, состояния разбора в макете нет.
                .opacity(isAnalyzing ? 0 : 1)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .overlay {
                    if isAnalyzing {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    }
                }
                // Тон приглушён: под непрозрачной чёрной заливкой системное
                // стекло не видно вовсе, и кнопка читается плоской краской.
                .liquidGlass(in: Capsule(), tint: Figma.graysBlack.opacity(0.86)) {
                    Capsule()
                        .fill(Figma.graysBlack)
                        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                }
                // Без этого нажималась только надпись: фон цель не расширяет.
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isAnalyzing)
        .accessibilityLabel(isAnalyzing ? "Разбираем запись" : (isRecording ? "Стоп" : "Слушать"))
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

            ForEach(history) { check in
                Spacer(minLength: 0).frame(height: 24)

                Text(check.date, format: .dateTime.day().month(.twoDigits).year())
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.43)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(check.orderedFindings) { finding in
                    Spacer(minLength: 0).frame(height: 16)
                    darkIssueCard(EngineIssue(title: finding.title, detail: finding.detail))
                }
            }
        }
    }

    /// Карточка со счётчиками, нода `46093:2410`: 370×96, две половины.
    private var statsCard: some View {
        HStack(spacing: 0) {
            counter(title: "Прослушиваний", value: history.count)
            counter(title: "Неисправности", value: history.reduce(0) { $0 + $1.findings.count })
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
        // Тот же компонент макета, только в тёмном режиме. Кромку на iOS 26
        // даёт само стекло, поэтому нарисованная обводка живёт лишь в
        // подложке для более старых систем — иначе кромок было бы две.
        Color.clear
            .liquidGlass(in: Self.cardShape, tint: Figma.darkCard) {
                Self.cardShape
                    .fill(Figma.darkCard)
                    .overlay(Self.cardShape.stroke(Color.white.opacity(0.10), lineWidth: 0.5))
            }
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
    /// Форма панели записи (нода `46105:4087`), 370 × 549.289, скругление 36.
    private static let panelShape = RoundedRectangle(cornerRadius: 36, style: .continuous)

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
            if let heard = nothingHeard {
                nothingHeardState(heard)
            } else {
                findingsList
                    .padding(.top, Findings.listTop)
            }
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
                showFindings = false
                nothingHeard = nil
                toggleRecording()
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
                ForEach(findings) { issue in
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
        // В макете это «Liquid Glass - Regular - Small», а не белая заливка.
        // Тень остаётся: она и держит карточку на подложке, разница между
        // её белым и фоном шторки всего три уровня.
        Color.clear
            .liquidGlass(in: Self.cardShape, tint: .white) {
                Self.cardShape.fill(Figma.backgroundsPrimary)
            }
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
            // В пустом состоянии «нашли» — неправда: не нашли ничего.
            Text(nothingHeard == nil ? "Вот что мы нашли" : "Запись")
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
                .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть")

                Spacer(minLength: 0)

                if nothingHeard == nil {
                    Button(action: approveFindings) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Figma.graysBlack))
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

    // MARK: - Действия

    private func syncTabBar() {
        hidesTabBar = showFindings || isModalRecording
    }

    private func toggleRecording() {
        if isRecording {
            meter.stop()
            activity = .idle
            analyse()
        } else {
            activity = .recording
            meter.start()
        }
    }

    /// Отдаёт запись на разбор и показывает результат. Шторка открывается
    /// только после ответа: показать её сразу и потом подменить содержимое
    /// значит соврать пользователю про то, что уже «нашли».
    private func analyse() {
        guard DiagnosisEndpoint.isConfigured, let recording = meter.lastRecording else {
            // Сервер не настроен — работаем как раньше, на заглушке. Это
            // честнее пустого экрана и совпадает с поведением «Карты» без ключа.
            nothingHeard = nil
            findings = IssuesStub.findings
            showFindings = true
            return
        }

        activity = .analyzing
        // Прошлый отказ к новой записи отношения не имеет: без сброса шторка
        // осталась бы пустой даже там, где находки есть.
        nothingHeard = nil
        analysisTask?.cancel()
        analysisTask = Task {
            let result: [EngineIssue]
            do {
                result = issues(from: try await CarDiagnosisClient.diagnose(fileURL: recording))
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription
                    ?? "Не удалось связаться с сервером"
                result = [EngineIssue(title: "Не удалось разобрать запись", detail: reason)]
            }
            guard !Task.isCancelled else { return }
            findings = result
            activity = .idle
            showFindings = true
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
    private func issues(from diagnosis: Diagnosis) -> [EngineIssue] {
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
                               detail: where_ + "модель ставит сюда " + percent(cause.p))
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
    private func verdictCard(_ diagnosis: Diagnosis) -> EngineIssue {
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

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))\u{00A0}%"
    }

    /// Подтверждённые находки уходят в базу. Порядок сохраняется номером:
    /// разбор ранжированный, а связь SwiftData порядок не гарантирует.
    private func approveFindings() {
        let check = EngineCheck()
        modelContext.insert(check)
        for (index, issue) in findings.enumerated() {
            let finding = EngineFinding(title: issue.title, detail: issue.detail, order: index)
            finding.check = check
            modelContext.insert(finding)
        }
        showFindings = false
    }
}

// MARK: - Данные

struct EngineIssue: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
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
