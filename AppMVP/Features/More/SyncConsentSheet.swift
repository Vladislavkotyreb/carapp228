import SwiftUI

/// Согласие на синхронизацию — до первой отправки на сервер (152-ФЗ). Три
/// строки: что уходит, что не уходит, где лежит и как удалить. Тексты
/// короткие (замечание пользователя 08.10.2026), но перечень данных полный:
/// согласие без перечня ничего не стоит. Сменили текст — сменили
/// `TripSync.consentVersion` и `CONSENT_VERSION` сервера.
struct SyncConsentSheet: View {
    var isBusy: Bool
    var error: String?
    let onAgree: () -> Void
    let onCancel: () -> Void

    /// Шторка по содержимому, а не во весь экран: на большой половина её
    /// пустовала. Крупный шрифт — тянется до полной высоты.
    static let detents: Set<PresentationDetent> = [.fraction(0.72), .large]

    private enum Layout {
        static let margin: CGFloat = 24
        static let icon: CGFloat = 28
        static let rowSpacing: CGFloat = 18
        static let button: CGFloat = 52
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.margin) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Синхронизация поездок")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Figma.labelsPrimary)
                Text("Поездки и пробег сохранятся на\u{00A0}сервере и\u{00A0}не\u{00A0}потеряются со\u{00A0}сменой телефона.")
                    .font(.system(size: 17))
                    .foregroundStyle(Figma.graysGray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Layout.rowSpacing) {
                row("arrow.up.circle", "Уходит: машины\u{00A0}— название и\u{00A0}пробег, поездки\u{00A0}— время и\u{00A0}расстояние.")
                row("lock", "Не уходит: госномер, VIN и\u{00A0}маршруты.")
                row("building.columns", "Сервер в\u{00A0}России. Удалить данные можно в\u{00A0}«Ещё».")
            }

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                if let error {
                    Text(error)
                        .font(.system(size: 15))
                        .foregroundStyle(Figma.accentsRed)
                        .frame(maxWidth: .infinity)
                }
                Text("Нажимая «Согласен», вы\u{00A0}соглашаетесь на\u{00A0}обработку этих данных.")
                    .font(.system(size: 13))
                    .foregroundStyle(Figma.graysGray)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                GlassProminentButton(title: "Согласен", isBusy: isBusy, action: onAgree)
                Button(action: onCancel) {
                    Text("Не сейчас")
                        .font(.system(size: 17))
                        .foregroundStyle(Figma.labelsPrimary)
                        .frame(maxWidth: .infinity, minHeight: Layout.button)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
        .padding(.horizontal, Layout.margin)
        .padding(.top, 32)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Figma.backgroundsPrimary)
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(Figma.accentsGreen)
                .frame(width: Layout.icon)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Figma.labelsPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
