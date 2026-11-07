import SwiftUI

/// Госномер плашкой (нода 45854:2921): «В 777 ОР | 777» — узкий SF, серый
/// текст на тёмной подложке, регион за тонкой чертой.
///
/// Один компонент на все экраны, где номер показывают, а не вводят: главная,
/// «Это ваш автомобиль?», поездка, выбор машины в находках. Раньше плашка была
/// нарисована дважды, а в поездке номер стоял строкой на другой подложке —
/// пользователь попросил единый стандарт (23.10.2026). Ввод номера —
/// `PlateInputField`.
///
/// Номер принимается в любом виде — «В777ОР777» или «В 777 ОР 777». Не
/// разбирается на части (неполный, иностранный) — та же плашка строкой.
/// Пустой номер — плашки нет вовсе: у машины, добавленной по названию,
/// номера нет.
struct PlateBadge: View {
    let plate: String

    private enum Layout {
        static let fontSize: CGFloat = 14
        static let tracking: CGFloat = -0.4
        static let spacing: CGFloat = 3.5
        static let dividerWidth: CGFloat = 0.875
        static let dividerHeight: CGFloat = 17.603
        static let horizontalPadding: CGFloat = 10.5
        static let verticalPadding: CGFloat = 3.5
        static let height: CGFloat = 28
        static let radius: CGFloat = 10.5
    }

    var body: some View {
        if !plate.trimmingCharacters(in: .whitespaces).isEmpty {
            content
                .font(.system(size: Layout.fontSize, weight: .semibold).width(.condensed))
                .tracking(Layout.tracking)
                .foregroundStyle(Figma.graysGray2)
                .lineLimit(1)
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.vertical, Layout.verticalPadding)
                .frame(height: Layout.height)
                .background(Figma.fillsPrimary, in: RoundedRectangle(cornerRadius: Layout.radius))
                // Читается номером целиком, а не четырьмя словами подряд.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Госномер \(PlateFormat.format(plate))")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let parts = PlateFormat.components(plate) {
            HStack(spacing: Layout.spacing) {
                HStack(spacing: Layout.spacing) {
                    Text(parts.letter)
                    Text(parts.digits)
                    Text(parts.letters)
                }

                Rectangle()
                    .fill(Figma.separatorsVibrant)
                    .frame(width: Layout.dividerWidth, height: Layout.dividerHeight)
                    .blendMode(.softLight)

                Text(parts.region)
            }
        } else {
            Text(plate)
        }
    }
}
