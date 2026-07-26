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
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 42), tint: Figma.darkCard) {
                        RoundedRectangle(cornerRadius: 42)
                            .fill(Figma.darkCard)
                            .overlay(RoundedRectangle(cornerRadius: 42)
                                .stroke(Color(white: 217 / 255), lineWidth: 0.5))
                    }
                    .motionRim(in: RoundedRectangle(cornerRadius: 42))
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
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .padding(.top, 16)
        .frame(height: 459)
        // в макете это стеклянная поверхность (Fill + Shadow + слой Glass Effect)
        // стекло тонируем белым и держим светлым: без этого над тёмной
        // подложкой поверхность темнеет и чёрный текст становится нечитаемым
        .liquidGlass(in: Self.shape, tint: .white) { Self.shape.fill(.white) }
        .environment(\.colorScheme, .light)
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
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.43)
                .foregroundStyle(Figma.vibrantControlsPrimary)

            HStack {
                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Figma.vibrantSecondary)
                        .frame(width: 44, height: 44)
                        // Кромку круглой кнопки даёт системное стекло
                        .liquidGlass(in: Circle()) {
                            Circle()
                                .fill(.white)
                                .overlay(Circle().stroke(Color(white: 232 / 255), lineWidth: 0.5))
                        }
                        .motionRim(in: Circle())
                        .shadow(color: .black.opacity(0.02), radius: 7.5, y: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть")
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}
