import SwiftUI

/// Громкость, доехавшая от микрофона до рамки по краям экрана.
///
/// Отдельный объект по той же причине, что `TabBarState` и `ScrollState`:
/// уровень обновляется на каждом аудиобуфере, десятки раз в секунду. Экран
/// держит его в `@State` — то есть хранит ссылку и **не подписан**, — поэтому
/// его `body` от громкости не зависит. Подписана одна `ListeningEdge`.
@MainActor
final class ListeningState: ObservableObject {
    /// Идёт ли запись. Управляет появлением и уходом рамки.
    @Published private(set) var isListening = false
    /// Сглаженная громкость 0…1.
    @Published private(set) var level: Double = 0

    func start() {
        guard !isListening else { return }
        isListening = true
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        level = 0
    }

    /// Пишется из `IssuesScreen` на каждом кадре уровня. Присваивание с
    /// проверкой: `AudioLevelMeter` уже сглаживает, но на паузах отдаёт одно и
    /// то же число, и без проверки рамка перерисовывалась бы впустую.
    func update(level new: Double) {
        guard isListening, abs(new - level) > 0.001 else { return }
        level = new
    }
}

/// Светящаяся рамка по кромке экрана на время прослушивания.
///
/// Референс — Apple Intelligence: свет живёт по самому краю дисплея, повторяет
/// его скругления, перелив бежит по кромке, а толщина и яркость отвечают на
/// происходящее. Палитра здесь своя, орба: рамка должна читаться продолжением
/// шара, а не чужой вставкой.
struct ListeningEdge: View {
    @ObservedObject var state: ListeningState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Толщина в покое записи и прибавка от громкости, в точках.
    private static let baseWidth: CGFloat = 3
    private static let gainWidth: CGFloat = 26

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !state.isListening)) { timeline in
            let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let level = state.level

            ZStack {
                if reduceTransparency {
                    // Прозрачность просили убрать — ореол убираем совсем,
                    // остаётся сплошная кромка. Она по-прежнему толстеет от
                    // громкости, то есть смысл индикатора сохраняется.
                    ScreenEdge()
                        .strokeBorder(Figma.orbBody,
                                      lineWidth: Self.baseWidth + Self.gainWidth * 0.4 * level)
                } else {
                    // Широкий тусклый ореол вглубь экрана и узкая яркая полоса
                    // по самому краю. Один слой читается наклейкой: у света
                    // должно быть и рассеяние, и ядро.
                    edge(width: Self.baseWidth * 4 + Self.gainWidth * level,
                         blur: 22, opacity: 0.45 + 0.35 * level, phase: phase * 0.35)
                    edge(width: Self.baseWidth + Self.gainWidth * 0.45 * level,
                         blur: 6, opacity: 0.7 + 0.3 * level, phase: phase * 0.6)
                }
            }
            // Свет складывается с тем, что под ним, а не закрашивает его.
            .blendMode(reduceTransparency ? .normal : .plusLighter)
            // Появление и уход не мгновенные: на старте записи рамка иначе
            // моргает, а на остановке обрывается.
            .opacity(state.isListening ? 1 : 0)
            .animation(.easeOut(duration: 0.45), value: state.isListening)
        }
        .ignoresSafeArea()
        // Рамка — индикатор, а не элемент управления: под ней всё должно
        // нажиматься, включая кнопку «Стоп».
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Один слой кромки. Перелив даёт угловой градиент, у которого едет фаза, —
    /// одной подкраски для ощущения «переливается» мало.
    private func edge(width: CGFloat, blur: CGFloat,
                      opacity: Double, phase: Double) -> some View {
        ScreenEdge()
            .strokeBorder(
                AngularGradient(
                    colors: [Figma.orbMint, Figma.orbBody, Figma.orbDeep,
                             Figma.orbCore, Figma.orbMint],
                    center: .center,
                    angle: .radians(phase)
                ),
                lineWidth: width
            )
            .blur(radius: blur)
            .opacity(opacity)
    }
}

/// Кромка экрана со скруглением дисплея.
///
/// Радиус не угадан и не взят из приватного `_displayCornerRadius`: он снят
/// замером чёрного угла с кадра. Значение по умолчанию — для нынешних
/// iPhone с Dynamic Island; на более старых углы заметно мельче, поэтому
/// выбор идёт по высоте экрана, а не одним числом на всех.
struct ScreenEdge: InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: Self.cornerRadius(for: rect.size) - inset,
                         style: .continuous)
            .path(in: rect.insetBy(dx: inset, dy: inset))
    }

    func inset(by amount: CGFloat) -> ScreenEdge {
        ScreenEdge(inset: inset + amount)
    }

    static func cornerRadius(for size: CGSize) -> CGFloat {
        // Экраны без Dynamic Island (SE и подобные) заметно менее скруглены.
        size.height >= 800 ? 55 : 47
    }
}
