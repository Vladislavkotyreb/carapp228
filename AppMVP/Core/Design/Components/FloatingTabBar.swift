import SwiftUI

/// Figma: «Tab Bar - iPhone» (node 45854:3333) — плавающая капсула на y = 779,
/// padding 25/16/25, выбранная вкладка подсвечена пилюлей Fills-Vibrant/Secondary #E0E0E0.
struct FloatingTabBar: View {
    @Binding var selection: Int

    @Namespace private var indicator

    private let tabs: [(symbol: String, title: String, color: Color)] = [
        ("car.fill", "Машина", Figma.accentsBlue),
        ("map.fill", "Карта", Figma.vibrantControlsPrimary),
        ("wrench.adjustable.fill", "Ошибки", Figma.vibrantControlsPrimary),
        ("ellipsis", "Ещё", Figma.labelsPrimary)
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { index in
                let tab = tabs[index]
                Button {
                    guard selection != index else { return }
                    withAnimation(Motion.selection) { selection = index }
                } label: {
                VStack(spacing: 0.5) {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 18, weight: .semibold))
                    Text(tab.title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineSpacing(2)
                }
                .foregroundStyle(index == selection ? Figma.accentsBlue : tab.color)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .padding(.bottom, 7)
                .frame(height: 54)
                .background {
                    if index == selection {
                        RoundedRectangle(cornerRadius: 100)
                            .fill(Figma.fillsVibrantSecondary)
                            .padding(.horizontal, -2)
                            .matchedGeometryEffect(id: "tab", in: indicator)
                    }
                }
                // HIG: вкладка — Button, а не жест: даёт нажатое состояние,
                // работу с клавиатурой и Switch Control. Цель нажатия ≥ 44pt.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(index == selection ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 2)
        // Liquid Glass: полупрозрачный материал, а не заливка — сквозь бар видно контент
        .background {
            Capsule()
                .fill(.clear)
                .liquidGlass(in: Capsule()) { Capsule().fill(.ultraThinMaterial) }
                .overlay(Capsule().stroke(Color(red: 232 / 255, green: 232 / 255, blue: 232 / 255), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.02), radius: 7.5, y: 8)
                .padding(-4)
        }
        .padding(.horizontal, 25)
        .padding(.top, 16)
        .padding(.bottom, 25)
        // экран идёт в тёмной схеме ради светлого статус-бара, но бар сам светлый
        .environment(\.colorScheme, .light)
    }
}
