import SwiftUI

// Модалка записи (нода `46105:4087`) — вынесена из `IssuesScreen` 25.09.2026
// без изменений вёрстки, чтобы кнопка-волна на главной открывала ровно её, а
// не похожую. Замечание пользователя: была системная шторка на пол-экрана —
// «есть же пример модалки, скопируй её».

/// Размеры и тексты модалки записи — общие для «Ошибок» и главной.
enum RecordingLayout {
    /// Карточка 370×549.289 на экране 402: 16 слева, 65.076 сверху.
    static let panelSize = CGSize(width: 370, height: 549.289)
    static let panelOffset = CGPoint(x: 16, y: 65.076)
    /// Форма панели записи (нода `46105:4087`), скругление 36.
    static let panelShape = RoundedRectangle(cornerRadius: 36, style: .continuous)

    static var heading: some View {
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
    static let screenCaption =
        "Поднесите телефон к двигателю или выхлопной\nтрубе и нажмите кнопку для начала\nдиагностики"
    static let panelCaption =
        "Поднесите телефон к двигателю или\nвыхлопной трубе и нажмите кнопку для\nначала диагностики"

    static func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16))
            .tracking(-0.31)
            .figmaLineHeight(21, fontSize: 16)
            .foregroundStyle(Figma.vibrantSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

/// Модалка записи, нода `46105:4087`: карточка 370×549.289, внутри
/// отступ 16, поэтому контент 338. Кнопку подставляет вызывающий: в
/// «Ошибках» у неё свой жест (тап и push-to-listen), на главной — просто «Стоп».
struct RecordingPanel<Action: View>: View {
    let level: Double
    @ViewBuilder let button: Action

    var body: some View {
        VStack(spacing: 0) {
            RecordingLayout.heading
            Spacer(minLength: 0).frame(height: 48)
            SoundOrb(level: level)
            Spacer(minLength: 0).frame(height: 24)
            RecordingLayout.caption(RecordingLayout.panelCaption)
            Spacer(minLength: 0).frame(height: 48)
            button
        }
        .padding(16)
        .background {
            // Заливка снята с рендера ноды `46105:4088` пипеткой: ровный
            // rgb(25,25,25) по всей панели, сверху донизу. Светлой кромки в
            // макете нет вовсе — стояла обводка 0.14, её убрал.
            // Тень остаётся: на затемнённом экране она отделяет панель от фона.
            RecordingLayout.panelShape
                .fill(Figma.recordingPanel)
                .shadow(color: .black.opacity(0.6), radius: 40, y: 12)
        }
    }
}

/// Вид кнопки «Слушать / Стоп» (нода `46105:4259`) — Glass Prominent в
/// светлом режиме, то есть **чёрная** пилюля со стеклом.
struct RecordingButtonLabel: View {
    let isRecording: Bool
    let isAnalyzing: Bool

    var body: some View {
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
            // Тон ослаблен с 0.86 до 0.55: под почти непрозрачной чёрной
            // заливкой системное стекло не читалось вовсе — замечание
            // пользователя «нет стекла». Кромка и блик теперь дышат, как
            // у кнопок главного экрана.
            .liquidGlass(in: Capsule(), tint: Figma.graysBlack.opacity(0.55)) {
                Capsule()
                    .fill(Figma.graysBlack)
                    .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
            }
            .motionRim(in: Capsule())
    }
}

/// Быстрое прослушивание с главной: та же модалка, что в «Ошибках», — то же
/// затемнение, та же панель, тот же переход и хаптик. Запись начинается сразу
/// (человек уже нажал волну), «Стоп» — разбор с индикатором в кнопке, дальше
/// `onResult`, и главная поднимает стандартную «Вот что мы нашли».
///
/// Лежит в иерархии всегда, а показывается флагом: переход у затемнения и у
/// панели разный (проявление и рост), и каждому нужен свой `if` внутри.
struct QuickListenOverlay: View {
    let isPresented: Bool
    let onResult: (DiagnosisCards.Outcome) -> Void

    @StateObject private var meter = AudioLevelMeter()
    @State private var isAnalyzing = false
    @State private var analysis: Task<Void, Never>?

    /// Точка роста панели — кнопка-волна в тулбаре (308, 84 на экране 402),
    /// пересчитанная в координаты панели. В «Ошибках» панель растёт из кнопки
    /// «Слушать» внизу; здесь та же идея из той кнопки, что её открыла.
    private static let growAnchor = UnitPoint(
        x: (308 - RecordingLayout.panelOffset.x) / RecordingLayout.panelSize.width,
        y: (84 - RecordingLayout.panelOffset.y) / RecordingLayout.panelSize.height)

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isPresented {
                // Затемнение плотнее макетного: там панель лежит поверх такого
                // же блока и просвечивать нечему, а у нас под ней страница.
                Figma.graysBlack.opacity(0.78)
                    .ignoresSafeArea()
                    .transition(.opacity)

                RecordingPanel(level: isAnalyzing ? 0 : meter.level) {
                    Button(action: stop) {
                        RecordingButtonLabel(isRecording: true, isAnalyzing: isAnalyzing)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(!isAnalyzing)
                    .accessibilityLabel(isAnalyzing ? "Разбираем запись" : "Стоп")
                }
                .frame(width: RecordingLayout.panelSize.width,
                       height: RecordingLayout.panelSize.height, alignment: .top)
                // По центру ширины, а не 16 от левого края: на экране 402 это те же
                // 16 с обеих сторон, а на 390 панель прижималась вправо (кадр 26.09).
                .frame(maxWidth: .infinity)
                .offset(y: RecordingLayout.panelOffset.y)
                .transition(.scale(scale: 0.12, anchor: Self.growAnchor)
                    .combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .animation(Motion.sheet, value: isPresented)
        // Хаптик раскрытия — тот же увесистый удар, что у модалки «Ошибок»;
        // закрытие отдаёт мягче.
        .sensoryFeedback(isPresented ? .impact(weight: .heavy) : .impact(flexibility: .soft),
                         trigger: isPresented)
        .onChange(of: isPresented) { _, shown in
            if shown {
                isAnalyzing = false
                meter.start()
            } else {
                meter.stop()
                analysis?.cancel()
            }
        }
        .onDisappear {
            meter.stop()
            analysis?.cancel()
        }
    }

    private func stop() {
        meter.stop()
        isAnalyzing = true
        let recording = meter.lastRecording
        analysis = Task {
            let outcome = await DiagnosisCards.run(recording: recording)
            guard !Task.isCancelled else { return }
            onResult(outcome)
        }
    }
}
