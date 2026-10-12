import SwiftUI

/// Figma «главная» (node 45883:3842) → Sheet, Detent = Medium.
/// Открывается по «Добавить ТО» и предлагает два пути: скан фото/PDF или ручное заполнение.
struct AddServiceChoiceSheet: View {
    private static let shape = UnevenRoundedRectangle(
        topLeadingRadius: 34, bottomLeadingRadius: 58,
        bottomTrailingRadius: 58, topTrailingRadius: 34
    )

    var title = "Добавление ТО"
    let onClose: () -> Void
    let onPickPhoto: () -> Void
    let onManual: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Spacer(minLength: 0)

            VStack(spacing: 16) {
                Button(action: onPickPhoto) {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 17))
                            .foregroundStyle(.white)

                        Text("Добавить фото или PDF")
                            .font(.system(size: 20, weight: .semibold))
                            .tracking(-0.45)
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .frame(height: 162)
                    // Серая, а не чёрная (просьба пользователя 06.10.2026):
                    // чёрная карточка на тёмной шторке читалась провалом.
                    // На ступень плотнее второй — это главный из двух путей.
                    .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: 42))
                    // Нажимается вся карточка, а не только надпись внутри.
                    .contentShape(RoundedRectangle(cornerRadius: 42))
                }

                Button(action: onManual) {
                    VStack(spacing: 0) {
                        Image(systemName: "long.text.page.and.pencil.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Figma.labelsPrimary)

                        Spacer(minLength: 0)

                        Text("Заполнить вручную")
                            .font(.system(size: 20, weight: .semibold))
                            .tracking(-0.45)
                            .foregroundStyle(Figma.labelsPrimary)
                    }
                    .frame(height: 47)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
                    .background(Figma.fillsQuaternary, in: RoundedRectangle(cornerRadius: 42))
                    .contentShape(RoundedRectangle(cornerRadius: 42))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .padding(.top, 16)
        .frame(height: 459)
        // Тёмная тема (нода 46225:7551): поверхность шторки тёмная. Карточка
        // «фото или PDF» в макете чёрная; у нас серая — см. выше.
        // Сплошная подложка, а не стекло с тоном: цвет тот же (замер
        // 28,28,30), но системная «Закрыть» — сама стекло, а стекло на
        // стекле почти не видно: кружок кнопки терялся (06.10.2026).
        .background(Self.shape.fill(Figma.sheetBackground))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .overlay(alignment: .top) {
            Capsule()
                .fill(Figma.vibrantPrimary)
                .frame(width: 58, height: 4)
                .padding(.top, 5)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    /// В макете у этой шторки только крестик — справа, слева пусто.
    private var toolbar: some View {
        SheetBar(title: title, closeSide: .trailing, onClose: onClose)
            .padding(.bottom, 10)
    }
}
