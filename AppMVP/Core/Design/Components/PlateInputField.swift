import SwiftUI

/// Ввод госномера «номерной рамкой»: поле во всю ширину шторки, крупные
/// знаки основной части и уменьшенный код региона за разделителем — как на
/// настоящем знаке. Просьба пользователя вместо обычного поля.
///
/// Символы появляются посимвольным морфом — нативный аналог веб-библиотеки
/// Torph (её саму в SwiftUI не перенести, это JS): каждый знак живёт своей
/// вью и въезжает масштабом с прозрачностью.
///
/// Ввод ловит невидимое `TextField` поверх рамки: своя раскладка клавиш нам
/// не нужна, а системная даёт и вставку, и диктовку, и автоповтор.
struct PlateInputField: View {
    @Binding var text: String
    var submitLabel: SubmitLabel = .go
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    /// Значимые символы без пробелов: рамка расставляет их сама.
    private var symbols: [Character] { Array(PlateFormat.significant(text)) }
    private var main: [Character] { Array(symbols.prefix(6)) }
    private var region: [Character] { Array(symbols.dropFirst(6)) }

    private static let mainTemplate = Array("А000АА")
    private static let regionTemplate = Array("000")

    var body: some View {
        HStack(spacing: 0) {
            plateGroup(main, template: Self.mainTemplate, size: 34)
                .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Figma.separatorsOnDark)
                .frame(width: 1, height: 52)

            VStack(spacing: 2) {
                plateGroup(region, template: Self.regionTemplate, size: 22)

                // «RUS» с флагом внизу — как на знаке; подпись служебная,
                // поэтому мелкая и приглушённая.
                Text("RUS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Figma.labelsTertiary)
            }
            .frame(width: 92)
        }
        .frame(height: 86)
        .frame(maxWidth: .infinity)
        .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: 26))
        .overlay {
            // Невидимое поле поверх рамки: тап в любое место открывает
            // клавиатуру, текст остаётся системным (вставка, диктовка).
            TextField("", text: Binding(
                get: { text },
                set: { text = PlateFormat.format($0) }))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .focused($focused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .accentColor(.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .onTapGesture { focused = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Госномер")
        .accessibilityValue(PlateFormat.format(text))
    }

    /// Группа знаков: введённые белые, оставшиеся — тусклый шаблон.
    private func plateGroup(_ entered: [Character], template: [Character],
                            size: CGFloat) -> some View {
        HStack(spacing: size * 0.12) {
            ForEach(Array(template.enumerated()), id: \.offset) { index, placeholder in
                let symbol = index < entered.count ? entered[index] : placeholder
                let filled = index < entered.count

                Text(String(symbol))
                    .font(.system(size: size, weight: .bold).monospacedDigit())
                    .foregroundStyle(filled ? Color.white : Figma.labelsTertiary)
                    // Морф символа: новый знак въезжает масштабом, старый
                    // гаснет — id по значению, иначе SwiftUI просто заменит
                    // строку без перехода.
                    .id("\(index)-\(symbol)-\(filled)")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: entered)
    }
}
