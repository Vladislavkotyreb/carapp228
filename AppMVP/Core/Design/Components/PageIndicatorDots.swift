import SwiftUI

/// Переключаемые страницы с отдельной доступной зоной нажатия для каждой точки.
struct PageIndicatorDots: View {
    let count: Int
    let currentIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Button { onSelect(index) } label: {
                    Circle()
                        .fill(index == currentIndex ? Figma.labelsPrimary : Figma.labelsTertiary)
                        .frame(width: 8, height: 8)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Страница \(index + 1) из \(count)")
                .accessibilityAddTraits(index == currentIndex ? .isSelected : [])
                .accessibilityIdentifier("onboarding-page-\(index)")
            }
        }
        .background(Color.white.opacity(0.07), in: Capsule())
    }
}
