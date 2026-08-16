import SwiftUI

/// Figma: «Button - Liquid Glass - Text», variant Style = Glass Prominent, Size = Large.
/// padding 20×16, radius 1000 (капсула), заливка Labels/Primary, лейбл 17pt белый.
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
        Button(action: action) {
            // Индикатор — оверлеем, а не обёрткой: цепочка модификаторов
            // лейбла должна остаться прежней, иначе кнопка сдвигается
            // на пиксель относительно макета.
            Text(title)
                .font(.system(size: Figma.buttonLabelSize, weight: weight))
                .tracking(tracking)
                .foregroundStyle(.white)
                .opacity(isBusy ? 0 : 1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .frame(height: lineHeight + 32)
                .overlay {
                    if isBusy {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                }
                .glassCapsule(prominent: true, fill: Figma.labelsPrimary)
                .shadow(color: .black.opacity(0.02), radius: 7.5, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(isBusy ? "\(title), выполняется" : title)
    }
}

extension View {
    /// Капсула кнопки из макета («Button - Liquid Glass - Text»). На iOS 26
    /// это системное стекло, ниже — заливка из макета.
    ///
    /// Не `buttonStyle(.glassProminent)`, хотя стиль в системе есть: он сам
    /// раскладывает лейбл и назначает ему свои отступы, а у наших кнопок
    /// геометрия снята с макета до точки. Материал берём системный, раскладку
    /// оставляем свою.
    func glassCapsule(prominent: Bool, fill: Color) -> some View {
        liquidGlass(in: Capsule(), tint: prominent ? fill : nil) {
            Capsule().fill(prominent ? AnyShapeStyle(fill) : AnyShapeStyle(Color.clear))
        }
    }
}

/// Figma: «Button - Liquid Glass - Text», variant Style = Glass, Size = Large.
/// Фон прозрачный, лейбл Labels-Vibrant-Controls/Primary #1A1A1A.
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
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .frame(height: lineHeight + 32)
        }
        .buttonStyle(.plain)
    }
}
