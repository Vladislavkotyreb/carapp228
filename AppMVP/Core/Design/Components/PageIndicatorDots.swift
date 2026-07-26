import SwiftUI

/// Figma: «Page Control», Controls container 64×24 — padding 12×8, точки 8×8 с шагом 8.
/// Подложка Ultrathin (белый 7%) на белом фоне визуально не читается — так в макете.
struct PageIndicatorDots: View {
    let count: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Figma.labelsPrimary : Figma.labelsTertiary)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.07), in: Capsule())
    }
}
