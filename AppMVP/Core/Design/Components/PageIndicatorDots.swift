import SwiftUI

/// Три тонких сегмента; доступная зона нажатия остаётся высотой 44 pt.
struct PageIndicatorDots: View {
    let count: Int
    let currentIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Button { onSelect(index) } label: {
                    Capsule()
                        .fill(index <= currentIndex ? Color.white : Color.white.opacity(0.2))
                        .frame(height: 3)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Страница \(index + 1) из \(count)")
                .accessibilityAddTraits(index == currentIndex ? .isSelected : [])
                .accessibilityIdentifier("onboarding-page-\(index)")
            }
        }
    }
}
