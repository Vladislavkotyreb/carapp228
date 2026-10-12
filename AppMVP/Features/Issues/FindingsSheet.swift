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
    /// Показывать нечего — шторка в пустом состоянии: без вопроса о машине,
    /// с ответами «Ещё раз» и «Закрыть».
    let empty: FindingsEmpty?
    /// Машины пользователя. Пусто — вопроса о прикреплении нет вовсе.
    let cars: [CarChoice]
    let onClose: () -> Void
    /// Сохранить находки. `nil` — не прикреплять ни к одной машине.
    let onApprove: (PersistentIdentifier?) -> Void
    /// «Ещё раз» из пустого состояния.
    let onRetry: () -> Void

    /// Прикреплять ли к машине. Включено сразу, когда слушали с экрана машины:
    /// там вопрос уже решён тем, откуда нажали «Послушать».
    @State private var attach: Bool
    /// Номер машины в `cars`, на которой остановилась карусель. Пишется
    /// прокруткой (`scrollPosition`) только при смене машины, не на каждом
    /// кадре. Номер, а не `PersistentIdentifier`: у только что добавленной
    /// машины идентификатор временный, автосохранение меняет его на
    /// постоянный — и сохранённый в состоянии id переставал совпадать ни с
    /// одной машиной (все точки гасли, кадр 26.09.2026). Id берётся из
    /// свежего `cars` в момент сохранения.
    @State private var selectedIndex: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(findings: [EngineIssue], empty: FindingsEmpty?,
         cars: [CarChoice], preselected: PersistentIdentifier?, attachByDefault: Bool,
         onClose: @escaping () -> Void,
         onApprove: @escaping (PersistentIdentifier?) -> Void,
         onRetry: @escaping () -> Void) {
        self.findings = findings
        self.empty = empty
        self.cars = cars
        self.onClose = onClose
        self.onApprove = onApprove
        self.onRetry = onRetry
        _attach = State(initialValue: attachByDefault && !cars.isEmpty)
        let start = cars.firstIndex { $0.id == preselected } ?? (cars.isEmpty ? nil : 0)
        _selectedIndex = State(initialValue: start)
    }

    private func approve() {
        onApprove(selectedChoice?.id)
    }

    private var selectedChoice: CarChoice? {
        guard attach, let index = selectedIndex, cars.indices.contains(index) else { return nil }
        return cars[index]
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
        static let iconSize: CGFloat = 32
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Контент уходит под тулбар, тот стоит на размытии с градиентом
            // — HIG, эталон пользователя; сплошная заливка верха — косяк,
            // который уже ловили на главном экране.
            VStack(spacing: 0) {
                if let empty {
                    emptyState(empty)
                } else {
                    findingsList
                }
            }
            .padding(.top, Findings.toolbarTop + Findings.toolbarHeight
                     + Findings.listTop)

            // Отдельным слоем от верха шторки и по её скруглению: фоном
            // панели размытие вылезало выше шторки (см. `AddServiceSheet`).
            SheetTopBlur(tint: Figma.sheetBackground)
                .frame(height: 118)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34))

            sheetToolbar
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

    /// Показывать нечего: неисправностей не названо, мотора не слышно или
    /// разбор не удался. Вопроса о машине и «Да, добавить ошибки» здесь нет —
    /// добавлять нечего; ответов два: «Ещё раз» и «Закрыть» (решение
    /// пользователя 04.10.2026). Тексты и значок — `FindingsEmpty`.
    private func emptyState(_ empty: FindingsEmpty) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(systemName: empty.symbol)
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Figma.vibrantSecondary)

            Spacer(minLength: 0).frame(height: 20)

            Text(empty.title)
                .font(.system(size: 22, weight: .bold))
                .figmaLineHeight(28, fontSize: 22, weight: .bold)
                .foregroundStyle(Figma.labelsPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            Spacer(minLength: 0).frame(height: 8)

            Text(empty.message)
                .font(.system(size: 15))
                .figmaLineHeight(20, fontSize: 15)
                .foregroundStyle(Figma.vibrantSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            Spacer(minLength: 0)

            // Тот же блок, что у находок: главная кнопка и вторая под ней.
            VStack(spacing: 12) {
                GlassProminentButton(title: "Ещё\u{00A0}раз", action: onRetry)
                GlassButton(title: "Закрыть", action: onClose)
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
    /// форме контейнера прячет её, пока высота растёт. Под вопросом —
    /// подзаголовок, зачем переключатель (просьба пользователя 04.10.2026):
    /// выключенный, он не объяснял, что будет, если его включить.
    private var attachSection: some View {
        VStack(spacing: Layout.attachGap) {
            HStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Figma.labelsPrimary)
                    .frame(width: Layout.iconSize + 4, height: Layout.iconSize + 4)
                    .background(Circle().fill(Figma.fillsTertiary))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Прикрепить к\u{00A0}машине?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Figma.labelsPrimary)

                    Text("Выберите машину, к\u{00A0}которой будет добавлена диагностика")
                        .font(.system(size: 13))
                        .foregroundStyle(Figma.labelsSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("Прикрепить к машине", isOn: $attach.animation(revealAnimation))
                    .labelsHidden()
                    .tint(Figma.accentsGreen)
            }

            if attach {
                carCarousel
                    .transition(carTransition)
            }
        }
        .padding(Layout.attachPadding)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Layout.rowRadius, style: .continuous)
            .fill(Figma.fillsTertiary))
        .clipShape(RoundedRectangle(cornerRadius: Layout.rowRadius, style: .continuous))
        .padding(.horizontal, 16)
    }

    /// Рост контейнера. Плавная кривая без отскока и подольше (0,38 → 0,55
    /// по замечанию «анимацию плавнее», 26.09.2026): пружина с отскоком
    /// дёргала бы список находок под контейнером.
    private var revealAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.55)
    }

    /// Подложка не спорит с ростом контейнера: проявляется, когда он уже
    /// пошёл вниз (задержка 0,12), и гаснет быстрее, чем он сжимается, —
    /// иначе при закрытии край клипа резал ещё видимые машины.
    private var carTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                .animation(.smooth(duration: 0.5).delay(0.12)),
            removal: .opacity.animation(.easeOut(duration: 0.18)))
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
                carPageControl
            }
        }
        .padding(.vertical, Layout.carPanelPadding)
        // Подложка чёрная, как фон главной: кадры каталога студийные на
        // чёрном и сливаются с ней — машины стоят без рамок.
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: Layout.carPanelRadius, style: .continuous))
    }

    /// Точки под номером — прежний вид: 6 pt, без подложки (пользователь
    /// вернул их 26.09.2026 после капсулы как на главной). Поведение — как у
    /// Page Control на главной: нажать на точку или вести пальцем по ряду —
    /// машина под пальцем выбирается, карусель докручивается к ней через
    /// `scrollPosition`. Видимый ряд маленький, поэтому зона касания
    /// раздвинута `contentShape` на 19 во все стороны — до 44 по высоте
    /// (HIG); раскладку это не трогает, как у «Записаться» на главной.
    private var carPageControl: some View {
        HStack(spacing: 6) {
            ForEach(cars.indices, id: \.self) { index in
                Circle()
                    .fill(index == selectedIndex ? Figma.labelsPrimary : Figma.labelsTertiary)
                    .frame(width: 6, height: 6)
            }
        }
        // Скраб по ряду. GeometryReader — в overlay ряда: снаружи он
        // растянул бы область, и координаты бы врали (так же на главной).
        .overlay {
            GeometryReader { g in
                Color.clear
                    .contentShape(Rectangle().inset(by: -19))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let index = scrubCar(x: value.location.x, width: g.size.width),
                                      index != selectedIndex else { return }
                                withAnimation(.easeOut(duration: 0.2)) { selectedIndex = index }
                            }
                            .onEnded { value in
                                guard let index = scrubCar(x: value.location.x, width: g.size.width)
                                else { return }
                                withAnimation(Motion.selection) { selectedIndex = index }
                            }
                    )
            }
        }
        .animation(Motion.selection, value: selectedIndex)
        .accessibilityElement()
        .accessibilityLabel("Машина")
        .accessibilityValue(selectedChoice?.name ?? "")
        .accessibilityAdjustableAction { direction in
            guard let current = selectedIndex else { return }
            let next = direction == .increment ? current + 1 : current - 1
            guard cars.indices.contains(next) else { return }
            withAnimation(Motion.selection) { selectedIndex = next }
        }
    }

    /// Машина под пальцем при скрабе по индикатору; nil — капсулы нет.
    private func scrubCar(x: CGFloat, width: CGFloat) -> Int? {
        guard width > 0, !cars.isEmpty else { return nil }
        let raw = Int(x / width * CGFloat(cars.count))
        return min(cars.count - 1, max(0, raw))
    }

    private var carScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Layout.carSpacing) {
                ForEach(Array(cars.enumerated()), id: \.offset) { index, choice in
                    CarChoiceItem(choice: choice, isSelected: index == selectedIndex,
                                  photoHeight: Layout.carPhotoHeight)
                        .containerRelativeFrame(.horizontal)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.86)
                                .opacity(phase.isIdentity ? 1 : 0.4)
                        }
                        .onTapGesture {
                            withAnimation(Motion.selection) { selectedIndex = index }
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
        .scrollPosition(id: $selectedIndex)
        .sensoryFeedback(.selection, trigger: selectedIndex)
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
                            BuyItemCard(item: item, carName: selectedChoice?.name)
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

    /// Тулбар: крестик слева, заголовок по центру, галочка справа.
    private var sheetToolbar: some View {
        // В пустом состоянии «нашли» — неправда: не нашли ничего, и
        // подтверждать нечего — галочки нет.
        SheetBar(title: empty == nil ? "Вот что мы нашли" : "Запись", onClose: onClose,
                 confirmLabel: "Добавить ошибки", onConfirm: empty == nil ? approve : nil)
            .frame(height: Findings.toolbarHeight)
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
    /// Загрузка кончилась ничем: ни своего фото, ни кадра каталога.
    @State private var failed = false

    /// Кадра не будет заведомо — показываем машину под тканью сразу, без
    /// пустоты на время загрузки.
    private var hasNoPicture: Bool {
        failed || (choice.photo == nil && choice.catalogSlug == nil)
    }

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
                } else if hasNoPicture {
                    // Та же машина под тканью, что на главной у машины без
                    // кадра (`CarPhoto`), — замечание пользователя 26.09.2026.
                    Image("CarPhoto").resizable().scaledToFit()
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
        failed = image == nil
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
    /// Итог разбора: находки или пустое состояние. Перечисление, а не два
    /// поля рядом: «пусто и при этом находки» выразить нельзя.
    enum Outcome {
        case findings([EngineIssue])
        case empty(FindingsEmpty)

        var cards: [EngineIssue] {
            if case .findings(let cards) = self { cards } else { [] }
        }

        var empty: FindingsEmpty? {
            if case .empty(let empty) = self { empty } else { nil }
        }
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
        // Пустые состояния тем же ключом: `clear` — «ничего не нашли»,
        // `unsure` — «судить не берёмся», `fail` — сбой. В симуляторе их
        // иначе не вызвать.
        switch ProcessInfo.processInfo.environment["BEEPY_STUB_DIAGNOSIS"] {
        case "1": return .findings(IssuesStub.findings)
        case "clear": return .empty(.nothingFound)
        case "unsure": return .empty(.unsure)
        case "fail": return failure(DiagnosisError.transport)
        default: break
        }
        #endif
        guard canDiagnose, let recording else {
            return .findings(IssuesStub.findings)
        }
        do {
            // Локальный разбор первым: модели лежат в бандле, сеть не
            // нужна вовсе. Сервер остаётся отладочным запасным путём на
            // случай сборки без моделей.
            let diagnosis = LocalDiagnosis.isAvailable
                ? try await LocalDiagnosis.diagnose(fileURL: recording)
                : try await CarDiagnosisClient.diagnose(fileURL: recording)
            return outcome(from: diagnosis)
        } catch {
            return failure(error)
        }
    }

    /// Разбор не удался — пустое состояние с причиной.
    private static func failure(_ error: Error) -> Outcome {
        .empty(.failed(reason: (error as? LocalizedError)?.errorDescription
            ?? "Разбор не\u{00A0}сработал"))
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
    static func outcome(from diagnosis: Diagnosis) -> Outcome {
        // Пусто или находки — решает чистая `FindingsEmpty.of`, там же и
        // объяснено, почему версии показываются только при вердикте
        // «неисправность». Здесь остаётся сборка карточек.
        if let empty = FindingsEmpty.of(modelLoaded: diagnosis.modelLoaded,
                                        isEngine: diagnosis.isEngine,
                                        verdict: diagnosis.verdict,
                                        heardExplanation: diagnosis.heard.explanation) {
            return .empty(empty)
        }

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
                               detail: where_ + percent(cause.p) + " среди версий",
                               advice: PartAdvice.line(cause.part),
                               part: cause.part)
        }

        if ranked.isEmpty {
            cards.append(EngineIssue(
                title: "Деталь не\u{00A0}определилась",
                detail: "Мало звука. Запишите ещё раз, ближе к\u{00A0}мотору"))
        }
        return .findings(cards)
    }

    /// Первая карточка: то единственное число, которое здесь означает
    /// вероятность в обычном смысле слова.
    ///
    /// Про сегменты здесь только оговорка, а не запрет. Жёсткий запрет тут
    /// стоял и оказался вреден: порог громкости в каскаде относительный, и
    /// ровно урчащий мотор кусков не даёт так же, как тишина. Отсеивать не мотор
    /// должен привратник, а это его работа, не наша.
    ///
    /// Карточка есть только у вердикта «неисправность»: «норма» и «не берусь
    /// судить» с 04.10.2026 — пустое состояние шторки (`FindingsEmpty`).
    static func verdictCard(_ diagnosis: Diagnosis) -> EngineIssue {
        let share = percent(diagnosis.faultProbability)
        let caveat = diagnosis.segmentCount == 0
            ? " Разбирали всю запись: чистого фрагмента не\u{00A0}нашлось."
            : ""
        return EngineIssue(title: "Похоже на неисправность",
                           detail: "Вероятность — \(share). Ниже версии, от\u{00A0}самой вероятной." + caveat)
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
                                        advice: issue.advice, part: issue.part, order: index)
            finding.check = check
            context.insert(finding)
        }
        return check
    }
}

/// Карточка расходника в ленте «Что можно купить» — общая для шторки после
/// записи и для сохранённого прослушивания. «Найти» — поиск в Яндекс
/// Маркете, с названием машины, если она известна. Номер в запрос не идёт.
struct BuyItemCard: View {
    let item: String
    let carName: String?

    @Environment(\.openURL) private var openURL

    /// 156, а не 136: «трансмиссионное» в 13 semibold не влезало в строку.
    static let width: CGFloat = 156
    private static let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    private static let iconSize: CGFloat = 32

    var body: some View {
        Button {
            if let url = PartAdvice.searchURL(item: item, carName: carName) { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: PartAdvice.symbol(forItem: item))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Figma.accentsYellow)
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .background(Circle().fill(Figma.fillsTertiary))

                Text(item)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.08)
                    .figmaLineHeight(18, fontSize: 13, weight: .semibold)
                    .foregroundStyle(Figma.labelsPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    // Без этого название обрезалось в одну строку
                    // («Масло трансмисс…») при зарезервированных двух — там,
                    // где расходников два и лента не выходит за край
                    // (прогон 06.10.2026, запись от 13.09 «Дифференциал»).
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text("Найти")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 13))
                .foregroundStyle(Figma.graysGray)
            }
            .padding(12)
            .frame(width: Self.width, alignment: .leading)
            .background(Self.shape.fill(Figma.fillsTertiary))
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item) — найти в\u{00A0}Яндекс Маркете")
    }
}

// MARK: - Сохранённое прослушивание

/// Сохранённое прослушивание — значения для шторки, которая открывается
/// тапом по записи в истории. Снимаются в момент тапа: шторка к базе не ходит.
struct SavedCheck {
    /// Своя на каждое открытие: шторка с этим `id` начинает с чистого
    /// состояния, а не с прокрутки прошлого прослушивания.
    let id = UUID()
    /// Название машины; `nil` — слушали без привязки к машине.
    let car: String?
    /// «26 сентября» или «31 декабря 2025».
    let date: String
    /// «56 400 км»; `nil` — пробега в записи нет.
    let mileage: String?
    let findings: [EngineIssue]
    /// Номер находки, по которой нажали. Шторка открывается сразу на ней:
    /// без этого тап по шестой карточке показывал первую, и свою приходилось
    /// искать прокруткой (прогон 06.10.2026).
    var focus: Int? = nil
}

extension SavedCheck {
    /// Переходник из модели — во вью-слое, как требует `Core/Pure`. Сама
    /// логика — подпись даты и поиск детали по названию — чистая и
    /// проверяется отдельно.
    init(_ check: EngineCheck, focus finding: EngineFinding? = nil,
         now: Date = .now, calendar: Calendar = .current) {
        let ordered = check.orderedFindings
        self.init(car: check.car?.name,
                  date: ListeningSummary.savedDate(check.date, now: now, calendar: calendar),
                  mileage: check.mileage.map { "\(NumberFormat.grouped($0))\u{00A0}км" },
                  findings: ordered.map { finding in
                      EngineIssue(title: finding.title, detail: finding.detail,
                                  advice: finding.advice,
                                  part: finding.part
                                      ?? DiagnosisVocabulary.partCode(forTitle: finding.title,
                                                                      extra: Self.stubTitles))
                  },
                  focus: finding.flatMap { tapped in ordered.firstIndex { $0 === tapped } })
    }

    /// Названия заглушки разбора: в словаре их нет, а в истории они есть.
    private static let stubTitles = IssuesStub.findings.compactMap { issue in
        issue.part.map { (title: issue.title, code: $0) }
    }
}

/// Шторка сохранённого прослушивания: что тогда нашли. Только смотреть.
///
/// Композиция — та же, что у «Изменения ТО» (`AddServiceSheet`, просьба
/// пользователя 06.10.2026): Detent = Large, сверху группа строк «Машина /
/// Дата / Пробег» как «Дата / Пробег» у ТО, ниже заголовок раздела и по
/// группе на находку, как «Работы». Те же числа: между разделами 32, под
/// заголовком 20, между группами 12, строка 52, радиус группы 26.
///
/// Верхняя панель — системный тулбар, а не нарисованный (та же просьба:
/// «HIG-панель из iOS 27»). По HIG «Toolbars»: стандартная кнопка закрытия
/// без подписи слева, короткий заголовок по центру (до 15 знаков), без
/// своих подложек и подкрашенных кнопок — стекло, форму кнопки и размытие
/// края прокрутки даёт система, и на iOS 27 панель выглядит как в iOS 27
/// без правок здесь. Главного действия справа нет: сохранять нечего.
struct SavedCheckSheet: View {
    let check: SavedCheck
    let onClose: () -> Void

    /// Отступ шторки от верха экрана — Detent = Large, как у формы ТО.
    /// Один на отступ и на зону захвата ручки, чтобы они не разошлись.
    static let topInset: CGFloat = 62

    private static let groupShape = RoundedRectangle(cornerRadius: 26)
    private static let sheetShape = UnevenRoundedRectangle(topLeadingRadius: 38,
                                                           topTrailingRadius: 38)

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        infoGroup

                        VStack(alignment: .leading, spacing: 20) {
                            Text("Находки")
                                .font(.system(size: 22, weight: .bold))
                                .figmaLineHeight(28, fontSize: 22, weight: .bold)
                                .foregroundStyle(Figma.labelsPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(spacing: 12) {
                                ForEach(check.findings) { issue in
                                    findingGroup(issue)
                                        .id(issue.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .onAppear {
                    // Первая находка и так на виду вместе с группой
                    // «Машина / Дата / Пробег» — прокручивать незачем.
                    guard let focus = check.focus, focus > 0,
                          check.findings.indices.contains(focus) else { return }
                    proxy.scrollTo(check.findings[focus].id, anchor: .top)
                }
            }
            .softTopScrollEdge()
            .background(Figma.sheetBackground)
            .navigationTitle("Прослушивание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { closeButton }
            }
        }
        // Без подкраски: по умолчанию кнопка панели берёт акцент приложения
        // и выходила синей. HIG просит монохромные кнопки тулбара, а акцент
        // у приложения белый.
        .tint(Figma.labelsPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Figma.sheetBackground)
        .clipShape(Self.sheetShape)
        .background {
            Self.sheetShape
                .fill(Figma.sheetBackground)
                .shadow(color: .black.opacity(0.18), radius: 18.75, y: 15)
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(Figma.vibrantPrimary)
                .frame(width: 58, height: 4)
                .padding(.top, 5)
        }
    }

    /// Стандартная кнопка закрытия. На iOS 26+ — системная роль: символ,
    /// стекло и подпись для VoiceOver ставит система. Раньше роли нет —
    /// тот же стандартный символ руками.
    @ViewBuilder
    private var closeButton: some View {
        if #available(iOS 26.0, *) {
            Button(role: .close, action: onClose)
        } else {
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Закрыть")
        }
    }

    // MARK: Группа «Машина / Дата / Пробег»

    private var infoGroup: some View {
        VStack(spacing: 0) {
            infoRow("Машина", value: check.car ?? "Без\u{00A0}машины")
            separator
            infoRow("Дата", value: check.date)
            if let mileage = check.mileage {
                separator
                infoRow("Пробег", value: mileage)
            }
        }
        .background(Figma.fillsTertiary, in: Self.groupShape)
    }

    /// Строка «подпись — значение»: подпись как у «Дата» в форме ТО,
    /// значение справа вторичным цветом — его не правят.
    private func infoRow(_ label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 17))
                .tracking(-0.43)
                .foregroundStyle(Figma.labelsPrimary)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 17))
                .tracking(-0.43)
                .foregroundStyle(Figma.labelsSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .accessibilityElement(children: .combine)
    }

    // MARK: Находка

    /// Группа на находку, как группа «Название / Сумма» у работы: строки
    /// через разделитель — что нашли, что это может быть, что купить.
    private func findingGroup(_ issue: EngineIssue) -> some View {
        let items = issue.part.map(PartAdvice.parts) ?? []
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .font(.system(size: 17, weight: .medium))
                    .tracking(-0.43)
                    .foregroundStyle(Figma.labelsPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(issue.detail)
                    .font(.system(size: 13))
                    .tracking(-0.08)
                    .figmaLineHeight(18, fontSize: 13)
                    .foregroundStyle(Figma.graysGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)

            if let meaning = issue.part.flatMap(PartAdvice.meaning) {
                separator
                VStack(alignment: .leading, spacing: 6) {
                    rowLabel("Что это может быть")
                    Text(meaning)
                        .font(.system(size: 15))
                        .tracking(-0.23)
                        .figmaLineHeight(20, fontSize: 15)
                        .foregroundStyle(Figma.labelsPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }

            if !items.isEmpty {
                separator
                VStack(alignment: .leading, spacing: 10) {
                    rowLabel("Что можно купить")
                        .padding(.horizontal, 16)
                    // Лента во всю ширину группы: первая карточка на поле
                    // текста, последняя уходит под край — видно, что листается.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(items, id: \.self) { item in
                                BuyItemCard(item: item, carName: check.car)
                            }
                        }
                    }
                    .contentMargins(.horizontal, 16, for: .scrollContent)
                }
                .padding(.vertical, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Figma.fillsTertiary, in: Self.groupShape)
        .clipShape(Self.groupShape)
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Figma.labelsSecondary)
    }

    private var separator: some View {
        Rectangle()
            .fill(Figma.separatorsOnDark)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

private extension View {
    /// Мягкий край прокрутки под тулбаром — размытие вместо подложки.
    /// Задан явно: на iOS 27 система по умолчанию ставила под панель плотную
    /// полосу с жёсткой кромкой, она резала верх первой группы и прятала
    /// ручку шторки (снято на симуляторе iOS 27.0, 06.10.2026). HIG
    /// «Toolbars»: своих подложек у панели не заводить, область панели
    /// отделять стилем края прокрутки.
    @ViewBuilder
    func softTopScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}
