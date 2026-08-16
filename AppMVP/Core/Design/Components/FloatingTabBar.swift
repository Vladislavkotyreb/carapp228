import SwiftUI

/// Состояние таббара, общее у экрана и самого бара.
///
/// Отдельный объект, а не `@State` внутри `CarMainView`, ровно по той же
/// причине, по которой там же живёт `ScrollState`: свёрнутость считается из
/// смещения прокрутки, а оно приходит на каждом кадре. Экран держит объект
/// в `@State` — то есть хранит ссылку и НЕ подписан на него, — поэтому его
/// `body` от прокрутки по-прежнему не зависит. Подписан один `FloatingTabBar`,
/// он и перерисовывается.
final class TabBarState: ObservableObject {
    /// Свёрнутый бар — «минимизация» из iOS 26: при прокрутке вниз таббар
    /// стягивается в пилюлю с одной активной вкладкой и отдаёт место контенту,
    /// при прокрутке вверх разворачивается обратно.
    @Published private(set) var isMinimized = false

    /// Смещение, от которого отсчитывается ход в текущую сторону.
    private var anchor: CGFloat = 0
    private var lastOffset: CGFloat = 0
    /// +1 — контент уезжает вверх (прокрутка вниз), −1 — обратно. 0 — ещё не знаем.
    private var direction: CGFloat = 0

    /// Сколько нужно проехать в одну сторону, чтобы бар сменил состояние.
    /// Порог заметно больше дрожания пальца: иначе бар мигает на месте.
    private static let threshold: CGFloat = 28

    /// У верха списка бар всегда развёрнут: там ещё не от чего освобождать место,
    /// а свёрнутый бар в покое читался бы как поломка.
    private static let topZone: CGFloat = 24

    /// Вызывается из читателя смещения прокрутки — на каждом кадре.
    /// Внутри только арифметика; `@Published` меняется лишь на самом переходе,
    /// то есть пару раз за жест.
    func track(offset: CGFloat) {
        let delta = offset - lastOffset
        lastOffset = offset
        // Дрожание пальца не считается сменой направления.
        guard abs(delta) > 0.5 else { return }

        // Развернулись — отсчёт до порога начинается заново. Без этого бар
        // менял состояние по накопленному пути и отвечал с задержкой.
        let current: CGFloat = delta > 0 ? 1 : -1
        if current != direction {
            direction = current
            anchor = offset
        }

        guard offset > Self.topZone else {
            anchor = offset
            set(false)
            return
        }

        if offset - anchor > Self.threshold { set(true) }
        if anchor - offset > Self.threshold { set(false) }
    }

    /// Развернуть принудительно: тап по свёрнутому бару или смена вкладки.
    func expand() {
        anchor = lastOffset
        set(false)
    }

    /// Раздел сменился — накопленные смещения относятся к чужому списку.
    func reset() {
        lastOffset = 0
        anchor = 0
        direction = 0
        set(false)
    }

    /// Только через это присваивание: условие выше держится истинным всё время,
    /// пока список едет дальше порога, и прямая запись рассылала бы
    /// `objectWillChange` на каждом кадре прокрутки — то есть перерисовывала бы
    /// бар шестьдесят раз в секунду ради значения, которое не менялось.
    private func set(_ value: Bool) {
        guard isMinimized != value else { return }
        isMinimized = value
    }
}

/// Figma: «Tab Bar - iPhone» (node 45854:3333) — плавающая капсула на y = 779,
/// padding 25/16/25, выбранная вкладка подсвечена пилюлей Fills-Vibrant/Secondary #E0E0E0.
///
/// Поведение — из HIG iOS 26 для таббара на Liquid Glass:
/// * бар сворачивается при прокрутке вниз и разворачивается при прокрутке вверх;
/// * иконка выбранной вкладки перетекает из контура в заливку и подпрыгивает;
/// * пилюля выделения переезжает пружиной, а не подменяется;
/// * вкладка отвечает на палец сжатием и тактильным щелчком;
/// * повторный тап по активной вкладке возвращает раздел в начало.
struct FloatingTabBar: View {
    @Binding var selection: Int
    @ObservedObject var state: TabBarState
    /// Повторный тап по уже выбранной вкладке.
    var onReselect: (Int) -> Void = { _ in }

    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Счётчики прыжков символов, по одному на вкладку. Нужны, чтобы
    /// `symbolEffect` срабатывал только у той иконки, которую выбрали:
    /// общий признак «выбрана» меняется сразу у двух вкладок, и прыгали обе.
    @State private var bounces = Array(repeating: 0, count: FloatingTabBar.tabs.count)

    private struct TabItem {
        let symbol: String
        /// Заливной вариант того же символа. HIG: выбранная вкладка — заливка,
        /// невыбранная — контур; цветом одним отличать их мало.
        let selectedSymbol: String
        let title: String
        let color: Color
    }

    private static let tabs: [TabItem] = [
        TabItem(symbol: "car", selectedSymbol: "car.fill",
                title: "Машина", color: Figma.accentsBlue),
        TabItem(symbol: "map", selectedSymbol: "map.fill",
                title: "Карта", color: Figma.vibrantControlsPrimary),
        TabItem(symbol: "wrench.adjustable", selectedSymbol: "wrench.adjustable.fill",
                title: "Ошибки", color: Figma.vibrantControlsPrimary),
        // У «ellipsis» заливного варианта нет — вкладка отличается пилюлей и цветом.
        TabItem(symbol: "ellipsis", selectedSymbol: "ellipsis",
                title: "Ещё", color: Figma.labelsPrimary)
    ]

    /// Ширина свёрнутой пилюли: иконка с самой длинной подписью плюс воздух.
    private static let minimizedWidth: CGFloat = 92

    /// Высота бара из макета. Держится постоянной и у свёрнутого: экран ставит
    /// бар по его верхней кромке, и меняющаяся высота двигала бы его по
    /// вертикали — сворачивание горизонтальное.
    private static let height: CGFloat = 54

    var body: some View {
        // Ширину бар должен знать на первом же кадре: развёрнутые вкладки
        // делят её поровну явными `frame(width:)`, а `maxWidth: .infinity`
        // не анимируется и в пилюлю не стягивается. Замер через `@State`
        // давал бы кадр не в ту ширину, поэтому берём геометрию раскладки.
        GeometryReader { geo in
            bar(available: geo.size.width)
                .frame(width: geo.size.width, alignment: .center)
        }
        .frame(height: Self.height)
        .padding(.horizontal, 25)
        .padding(.top, 16)
        .padding(.bottom, 25)
        // экран идёт в тёмной схеме ради светлого статус-бара, но бар сам светлый
        .environment(\.colorScheme, .light)
        // HIG: смена вкладки — .selection, не impact
        .sensoryFeedback(.selection, trigger: selection)
        .animation(Motion.tabBar(reduceMotion: reduceMotion), value: state.isMinimized)
    }

    private func bar(available: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Self.tabs.indices, id: \.self) { index in
                tab(index)
                    .frame(width: width(of: index, available: available))
            }
        }
        .padding(.horizontal, 2)
        // Режем по границе самого бара: на сворачивании вкладки ужимаются в
        // ноль, но рисуются в своей натуральной ширине — без клипа иконки
        // повисали бы снаружи стекла. Клип идёт ПОСЛЕ горизонтального
        // паддинга, поэтому пилюля выделения, торчащая из вкладки на 2pt,
        // остаётся целой.
        .clipped()
        // Liquid Glass: полупрозрачный материал, а не заливка — сквозь бар видно контент
        .background { glass }
    }

    private var glass: some View {
        Capsule()
            .fill(.clear)
            // Обводку даёт само стекло. Нарисованная поверх капсула
            // давала вторую кромку — её убрали.
            .liquidGlass(in: Capsule(), kind: reduceTransparency ? .painted : .regular) {
                // Reduce Transparency: сквозь бар не должно быть видно контента,
                // иначе подписи вкладок читаются поверх фотографии машины.
                Capsule().fill(reduceTransparency
                               ? AnyShapeStyle(Figma.backgroundsPrimary)
                               : AnyShapeStyle(Material.ultraThinMaterial))
            }
            .motionRim(in: Capsule())
            .shadow(color: .black.opacity(0.02), radius: 7.5, y: 8)
            .padding(-4)
    }

    private func tab(_ index: Int) -> some View {
        let item = Self.tabs[index]
        let isSelected = index == selection

        return Button {
            tap(index)
        } label: {
            VStack(spacing: 0.5) {
                Image(systemName: isSelected ? item.selectedSymbol : item.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    // Контур перетекает в заливку перерисовкой самого символа,
                    // а не подменой картинки: подмена мигает.
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, options: .speed(1.4),
                                  value: reduceMotion ? 0 : bounces[index])

                Text(item.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineSpacing(2)
            }
            .foregroundStyle(isSelected ? Figma.accentsBlue : item.color)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .padding(.bottom, 7)
            .frame(height: Self.height)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 100)
                        .fill(Figma.fillsVibrantSecondary)
                        .padding(.horizontal, -2)
                        .matchedGeometryEffect(id: "tab", in: indicator)
                        // У свёрнутого бара выделять нечего: пилюлей стала сама
                        // капсула стекла. Гасим прозрачностью, а не условием, —
                        // условие сломало бы matchedGeometryEffect.
                        .opacity(state.isMinimized ? 0 : 1)
                }
            }
            // HIG: вкладка — Button, а не жест: даёт нажатое состояние,
            // работу с клавиатурой и Switch Control. Цель нажатия ≥ 44pt.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressStyle())
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        // Свёрнутая вкладка не просто нулевой ширины — она ещё и не должна
        // отвечать на касания по своему бывшему месту.
        .opacity(isHidden(index) ? 0 : 1)
        .allowsHitTesting(!isHidden(index))
    }

    private func isHidden(_ index: Int) -> Bool {
        state.isMinimized && index != selection
    }

    /// Развёрнутый бар делит ширину поровну, как в макете; свёрнутый оставляет
    /// только активную вкладку — остальные ужимаются в ноль, и стекло
    /// стягивается вместе с ними. `nil`, пока ширины ещё нет: там нечего делить.
    private func width(of index: Int, available: CGFloat) -> CGFloat? {
        guard available > 0 else { return nil }
        guard state.isMinimized else {
            // −4 — горизонтальный паддинг бара: без него сумма вкладок вылезала
            // бы за отведённую ширину.
            return (available - 4) / CGFloat(Self.tabs.count)
        }
        return index == selection ? Self.minimizedWidth : 0
    }

    private func tap(_ index: Int) {
        guard selection != index else {
            // Свёрнутый бар разворачивается по тапу — так же ведёт себя
            // минимизированный таббар iOS 26. Развёрнутый отдаёт повторный
            // тап разделу: HIG просит возвращать его в начало.
            if state.isMinimized { state.expand() } else { onReselect(index) }
            return
        }
        bounces[index] += 1
        withAnimation(Motion.tabSelection(reduceMotion: reduceMotion)) { selection = index }
        // Переход в другой раздел всегда показывает бар целиком: свёрнутость
        // относилась к прокрутке предыдущего.
        state.expand()
    }
}

/// Нажатие на вкладку: короткое сжатие с возвратом пружиной. Системное стекло
/// iOS 26 отвечает на палец само (`Glass.interactive`), но у вкладки внутри
/// общей капсулы своего стекла нет — отклик рисуем сами.
private struct TabPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .animation(Motion.tabPress, value: configuration.isPressed)
    }
}
