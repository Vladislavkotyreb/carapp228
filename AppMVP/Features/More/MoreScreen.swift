import SwiftUI

/// Раздел «Ещё». Дизайна на него в Figma нет, поэтому содержание минимальное —
/// как у ненастроенной карты. До правки вкладка не рисовала вообще ничего:
/// переключение на неё выглядело поломкой, а не пустым разделом.
struct MoreScreen: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Figma.vibrantSecondary)

            Text("Скоро здесь будет больше")
                .font(.system(size: 22, weight: .bold))
                .figmaLineHeight(28, fontSize: 22, weight: .bold)
                .foregroundStyle(Figma.labelsPrimary)

            Text("Профиль, напоминания и настройки\nпоявятся в следующих версиях")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Figma.vibrantSecondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Figma.mainBackground)
    }
}
