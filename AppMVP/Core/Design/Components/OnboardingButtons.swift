import SwiftUI

/// Figma: «Button - Liquid Glass - Text», variant Style = Glass Prominent, Size = Large.
/// padding 20×16, radius 1000 (капсула), заливка Labels/Primary, лейбл 17pt белый.
/// Высота = 16 + line-height + 16 (50 при lh 18, 54 при lh 22).
struct GlassProminentButton: View {
    let title: String
    var lineHeight: CGFloat = 22
    var weight: Font.Weight = .regular
    var tracking: CGFloat = -0.43
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Figma.buttonLabelSize, weight: weight))
                .tracking(tracking)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .frame(height: lineHeight + 32)
                .background(Figma.labelsPrimary, in: Capsule())
                .shadow(color: .black.opacity(0.02), radius: 7.5, y: 8)
        }
        .buttonStyle(.plain)
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
