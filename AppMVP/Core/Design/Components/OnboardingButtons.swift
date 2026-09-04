import SwiftUI

/// Figma: «Button - Liquid Glass - Text», variant Style = Glass Prominent, Size = Large.
/// padding 20×16, radius 1000 (капсула), заливка Labels/Primary, лейбл 17pt
/// контрастный к ней. В тёмной теме это белая капсула с чёрным лейблом —
/// акцент кнопок оставлен белым по прямому указанию пользователя.
/// Высота = 16 + line-height + 16 (50 при lh 18, 54 при lh 22).
struct GlassProminentButton: View {
    let title: String
    var lineHeight: CGFloat = 22
    var weight: Font.Weight = .regular
    var tracking: CGFloat = -0.43
    /// Идёт запрос: вместо лейбла индикатор, нажатие заблокировано.
    /// Состояния загрузки в макете нет, поэтому геометрию кнопки не меняем.
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(ProminentCapsuleStyle())
            .disabled(isBusy)
            .accessibilityLabel(isBusy ? "\(title), выполняется" : title)
    }

    /// Индикатор — оверлеем, а не обёрткой: цепочка модификаторов лейбла
    /// должна остаться прежней, иначе кнопка сдвигается относительно макета.
    private var label: some View {
        Text(title)
            .font(.system(size: Figma.buttonLabelSize, weight: weight))
            .tracking(tracking)
            .opacity(isBusy ? 0 : 1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .frame(height: lineHeight + 32)
            .overlay {
                if isBusy {
                    ProgressView().progressViewStyle(.circular).tint(.black)
                }
            }
    }
}

/// «Button - Liquid Glass - Text», Style = Glass Prominent, Size = Large
/// (`45824:2607` в макете, 370×54, радиус 1000).
///
/// Своим `ButtonStyle`, а не системным `.glassProminent`: системный сам
/// назначает лейблу отступы и высоту, а здесь она снята с макета до точки.
/// **Что берётся у системы — отклик на нажатие**: до этого кнопка на палец не
/// отвечала вовсе, потому что стояла `.buttonStyle(.plain)`, которая гасит и
/// подсветку, и сжатие. Материал капсулы тоже системный.
private struct ProminentCapsuleStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .glassCapsule(prominent: true, fill: Figma.labelsPrimary)
            .shadow(color: .black.opacity(0.02), radius: 7.5, y: 8)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Motion.tabPress, value: configuration.isPressed)
            // Вся капсула — цель нажатия, а не только буквы внутри неё.
            .contentShape(Capsule())
    }
}

extension View {
    /// Капсула кнопки из макета («Button - Liquid Glass - Text»). На iOS 26
    /// это системное стекло, ниже — заливка из макета.
    ///
    /// Материал системный, раскладка своя: системный стиль назначает лейблу
    /// собственные отступы, а геометрия наших кнопок снята с макета до точки.
    func glassCapsule(prominent: Bool, fill: Color) -> some View {
        // Тон приглушён до 0.86: при непрозрачной заливке `glassEffect` под ней
        // не виден вовсе — стекло есть, а выглядит плоской краской. Замер
        // системной кнопки показал, что своей она даёт 49pt против макетных 54,
        // поэтому капсула остаётся своей, а от системы берётся материал.
        liquidGlass(in: Capsule(), tint: prominent ? fill.opacity(0.86) : nil) {
            Capsule().fill(prominent ? AnyShapeStyle(fill) : AnyShapeStyle(Color.clear))
        }
    }
}

/// Figma: «Button - Liquid Glass - Text», variant Style = Glass, Size = Large.
/// Фон прозрачный, лейбл Labels-Vibrant-Controls/Primary (в тёмной теме #F5F5F5).
struct GlassButton: View {
    let title: String
    var lineHeight: CGFloat = 22
    var color: Color = Figma.vibrantControlsPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Figma.buttonLabelSize))
                .tracking(-0.43)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .frame(height: lineHeight + 32)
        }
        .buttonStyle(PlainCapsuleStyle(color: color))
    }
}

/// «Button - Liquid Glass - Text», Style = Glass: фона нет, есть отклик.
/// Отдельным стилем по той же причине, что и у заметной кнопки: `.plain`
/// гасит любую реакцию на палец, и кнопка ощущается мёртвой.
private struct PlainCapsuleStyle: ButtonStyle {
    let color: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(color)
            .opacity(configuration.isPressed ? 0.45 : (isEnabled ? 1 : 0.4))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Motion.tabPress, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// «Button - Content Area», Style = Bordered (`45883:4144` в макете): капсула
/// 370×50 с подложкой и лейблом акцентного цвета.
///
/// Отдельный стиль, а не `.background()` на лейбле: подложка, нажатое
/// состояние и цель касания — свойства кнопки, а не текста внутри неё.
/// С прежней `.buttonStyle(.plain)` кнопка на палец не отвечала.
struct ContentAreaStyle: ButtonStyle {
    let tint: Color
    let fill: Color

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .background(fill, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Motion.tabPress, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}
