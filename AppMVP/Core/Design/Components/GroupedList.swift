import SwiftUI

/// Сгруппированный список, как `List(.insetGrouped)`: строки «название —
/// значение» на серой подложке, тонкий разделитель от поля, заголовок над
/// группой и подпись под ней.
///
/// Первые компоненты дизайн-системы Beepy (23.10.2026): раньше одинаковые
/// строки жили своими копиями в «Ещё» и на экране поездки. Перечень
/// компонентов и правила — docs/DESIGN_SYSTEM.md.
enum GroupedLayout {
    /// Высота строки — выше цели касания 44 по HIG.
    static let row: CGFloat = 52
    /// Радиус группы — как у карточек на главной.
    static let radius: CGFloat = 26
    /// Поле строки и отступ разделителя.
    static let inset: CGFloat = 16
}

/// Группа строк на серой подложке.
struct GroupedCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: GroupedLayout.radius))
    }
}

/// Строка: название, значение справа и значок — шеврон, стрелки меню или
/// ничего (`icon: nil`) у строки, которая только показывает.
struct GroupedRowLabel: View {
    let title: String
    var value = ""
    /// «Включено», «подключён» — зелёным.
    var highlighted = false
    var icon: String? = "chevron.right"

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(Figma.labelsPrimary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 17))
                .foregroundStyle(highlighted ? Figma.accentsGreen : Figma.graysGray)
                .lineLimit(1)
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Figma.graysGray)
            }
        }
        .padding(.horizontal, GroupedLayout.inset)
        .frame(height: GroupedLayout.row)
        .contentShape(Rectangle())
    }
}

/// Строка-кнопка: название, значение справа и шеврон.
struct GroupedLinkRow: View {
    let title: String
    var value = ""
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GroupedRowLabel(title: title, value: value, highlighted: highlighted)
        }
        .buttonStyle(CardPressStyle())
        // Название — подписью, значение — значением: VoiceOver читает
        // «Поездки, 12», а тесты находят строку по названию.
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

/// Разделитель строк — от поля, как у системных списков.
struct GroupedSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Figma.separatorsOnDark)
            .frame(height: 0.5)
            .padding(.leading, GroupedLayout.inset)
    }
}

/// Заголовок группы.
struct SectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Figma.labelsPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Подпись под группой: зачем строки выше и что с ними делать.
struct GroupFootnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Figma.graysGray)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, GroupedLayout.inset)
    }
}
