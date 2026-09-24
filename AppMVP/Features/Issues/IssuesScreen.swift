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

    /// Машина, которую слушаем, — та, что открыта на «Машине». Прослушивание
    /// сохраняется к ней вместе с пробегом: без этого история не знала, чей
    /// это мотор, и в заявку на ТО её было не приложить.
    var car: Car?

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

    /// Палец на кнопке «Слушать» (своя пресс-анимация вместо ButtonStyle).
    @State private var pressingListen = false
    /// Запись начата зажатием и держится до отпускания пальца.
    @State private var holdListening = false
    @State private var holdTask: Task<Void, Never>?

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

                // Панель вырастает из места кнопки «Слушать»: scale с якорем
                // в нижней части (кнопка стоит там). matchedGeometryEffect
                // лагал — он перекладывал стекло и шар на каждом кадре;
                // простой scale-переход даёт тот же жест за копейки.
                RecordingPanel(level: meter.level) { listenButton() }
                    .frame(width: RecordingLayout.panelSize.width,
                           height: RecordingLayout.panelSize.height, alignment: .top)
                    .offset(x: RecordingLayout.panelOffset.x, y: RecordingLayout.panelOffset.y)
                    .transition(.scale(scale: 0.12,
                                       anchor: .init(x: 0.5, y: 0.92))
                        .combined(with: .opacity))
            }
        }
        // Хаптик раскрытия — увесистый одиночный удар, как у длинного нажатия
        // на остров; закрытие отдаёт мягче.
        .sensoryFeedback(isModalRecording ? .impact(weight: .heavy)
                                          : .impact(flexibility: .soft),
                         trigger: isModalRecording)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Figma.graysBlack)
        .animation(Motion.sheet, value: isRecording)
        .animation(Motion.sheet, value: history.count)
        // Возврат в покой обязателен. Раньше его не было: отменённый разбор
        // выходит по `guard !Task.isCancelled` мимо сброса флага, и кнопка
        // оставалась навсегда отключённой с индикатором. Прерванная запись
        // залипала так же — «Стоп» на остановленном метре.
        .onDisappear { meter.stop(); analysisTask?.cancel(); activity = .idle }
        .bottomSheet(isPresented: $showFindings) {
            FindingsSheet(findings: findings, nothingHeard: nothingHeard,
                          onClose: { showFindings = false },
                          onApprove: approveFindings,
                          onRetry: {
                              showFindings = false
                              nothingHeard = nil
                              toggleRecording()
                          })
        }
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
                RecordingLayout.heading
                Spacer(minLength: 0).frame(height: 48)
                // Пока истории нет, шар оживает прямо здесь: модалки не будет.
                SoundOrb(level: isRecording && !hasHistory ? meter.level : 0)
                Spacer(minLength: 0).frame(height: 24)
                RecordingLayout.caption(RecordingLayout.screenCaption)
                Spacer(minLength: 0).frame(height: buttonGap)
                listenButton()

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

    /// Аннотация макета к ноде `46105:4259`: «кнопка работает по принципу
    /// старт стоп».
    ///
    /// Стиль — Glass Prominent в светлом режиме, то есть **чёрная** пилюля со
    /// стеклом. Раньше стояла заливка `darkCard` (#1A1A1A) с обводкой, и она
    /// читалась серой.
    /// Кнопка живёт в двух режимах — просьба пользователя, референс
    /// «переключение музыки в Dynamic Island»:
    /// - короткий тап — старт/стоп, как и раньше;
    /// - зажатие — push-to-listen: через 0.25 с запись начинается (модалка
    ///   вырастает из кнопки с увесистым хаптиком) и идёт, ПОКА палец на
    ///   экране; отпустил — стоп и разбор.
    /// Свой жест вместо Button: системному не различить «тап» и «держу».
    private func listenButton() -> some View {
        // Вид кнопки — общий с модалкой быстрого прослушивания на главной.
        RecordingButtonLabel(isRecording: isRecording, isAnalyzing: isAnalyzing)
            // Нажатие как у остальных кнопок (масштаб 0.97 + гашение).
            .opacity(pressingListen ? 0.6 : 1)
            .scaleEffect(pressingListen ? 0.97 : 1)
            .animation(Motion.tabPress, value: pressingListen)
            .contentShape(Capsule())
            .gesture(listenGesture)
            .allowsHitTesting(!isAnalyzing)
            .accessibilityLabel(isAnalyzing ? "Разбираем запись"
                                : (isRecording ? "Стоп" : "Слушать"))
            .accessibilityAddTraits(.isButton)
    }

    private var listenGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressingListen else { return }
                pressingListen = true
                guard !isRecording else { return }
                // Планируем вход в push-to-listen: если палец всё ещё на
                // кнопке через 0.25 с — запись стартует, не дожидаясь
                // отпускания.
                holdTask?.cancel()
                holdTask = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, pressingListen, !isRecording,
                          !isAnalyzing else { return }
                    holdListening = true
                    toggleRecording()
                }
            }
            .onEnded { _ in
                pressingListen = false
                holdTask?.cancel()
                if holdListening {
                    // Отпустил — стоп и разбор, как у рации.
                    holdListening = false
                    if isRecording { toggleRecording() }
                } else {
                    // Короткое касание — прежний старт/стоп.
                    toggleRecording()
                }
            }
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

            // Прослушивания сгруппированы по календарному дню: раньше каждое
            // печатало свою дату, и три записи одного дня давали три
            // одинаковых заголовка подряд.
            ForEach(historyByDay, id: \.day) { group in
                Spacer(minLength: 0).frame(height: 24)

                Text(group.day, format: .dateTime.day().month(.twoDigits).year())
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.43)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(group.checks) { check in
                    ForEach(check.orderedFindings) { finding in
                        Spacer(minLength: 0).frame(height: 16)
                        darkIssueCard(EngineIssue(title: finding.title,
                                                  detail: finding.detail,
                                                  advice: finding.advice))
                    }
                }
            }
        }
    }

    /// История по дням, свежие сверху; внутри дня порядок исходной выборки
    /// (она уже отсортирована по дате вниз).
    private var historyByDay: [(day: Date, checks: [EngineCheck])] {
        let calendar = Calendar.current
        return Dictionary(grouping: history) { calendar.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, checks: $0.value) }
    }

    /// Карточка со счётчиками, нода `46093:2410`: 370×96, две половины.
    /// Поверхность общая с плитками главного (`darkCardSurface`) — их
    /// «стекло» после оптимизации то же самое.
    private var statsCard: some View {
        HStack(spacing: 0) {
            counter(title: "Прослушиваний", value: history.count)
            counter(title: "Неисправности", value: history.reduce(0) { $0 + $1.findings.count })
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .background(darkCardSurface)
    }

    /// Типографика — один в один колонка плиток главного экрана
    /// (`statColumn`): узкий SF 14/−0.4 подписи в боксе 20, значение
    /// 20 semibold без трекинга в боксе 25, между ними 2. Референс
    /// пользователя; расходились и кегль подписи (13), и трекинги.
    private func counter(title: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .semibold).width(.condensed))
                .tracking(-0.4)
                .foregroundStyle(Figma.vibrantSecondary)
                .frame(height: 20)

            Text("\(value)")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(height: 25)
        }
        .frame(height: 47)
        .frame(maxWidth: .infinity)
    }

    /// Карточка неисправности на тёмном экране, нода `46093:2421`: 370×102.
    private func darkIssueCard(_ issue: EngineIssue) -> some View {
        IssueCardBody(issue: issue, title: .white, detail: Figma.vibrantSecondary)
            .background(darkCardSurface)
    }

    /// Скругление карточки. 26 было мало: по замеру рендера макета белое
    /// начинается в 15pt от края на 6px ниже верха карточки, в 6pt на 15px и в
    /// 2pt на 22px — это радиус около 34, у 26 выходило 9 / 3 / 1.
    static let cardRadius: CGFloat = 34

    private static let cardShape = RoundedRectangle(cornerRadius: cardRadius,
                                                    style: .continuous)

    private var darkCardSurface: some View {
        // Общий painted-рецепт (LiquidGlass.swift): живое стекло на каждой
        // карточке пересчитывалось каждый кадр и подлагивало.
        Color.clear.darkCardSurface(in: Self.cardShape)
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
    /// значит соврать пользователю про то, что уже «нашли». Сам разбор —
    /// `DiagnosisCards`, общий с быстрым прослушиванием на главной.
    private func analyse() {
        // Прошлый отказ к новой записи отношения не имеет: без сброса шторка
        // осталась бы пустой даже там, где находки есть.
        nothingHeard = nil
        guard DiagnosisCards.canDiagnose, meter.lastRecording != nil else {
            findings = IssuesStub.findings
            showFindings = true
            return
        }
        activity = .analyzing
        let recording = meter.lastRecording
        analysisTask?.cancel()
        analysisTask = Task {
            let outcome = await DiagnosisCards.run(recording: recording)
            guard !Task.isCancelled else { return }
            findings = outcome.cards
            nothingHeard = outcome.nothingHeard
            activity = .idle
            showFindings = true
        }
    }

    /// Подтверждённые находки уходят в базу. Порядок сохраняется номером:
    /// разбор ранжированный, а связь SwiftData порядок не гарантирует.
    private func approveFindings() {
        EngineCheck.record(findings, car: car, in: modelContext)
        showFindings = false
    }
}

// MARK: - Данные

struct EngineIssue: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    /// Что проверить и что обычно меняют — `PartAdvice`. Есть только у карточек
    /// с названной деталью: у вердикта и у сообщений об ошибке советовать нечего.
    var advice: String? = nil
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
