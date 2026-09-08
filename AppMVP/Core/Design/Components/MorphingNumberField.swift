import SwiftUI

/// Ввод числа с посимвольным морфом — тот же приём, что у номерной рамки
/// (`PlateInputField`): каждая цифра живёт своей вью и въезжает масштабом,
/// разряды перестраиваются пружиной. Нативный аналог веб-Torph.
///
/// Текст остаётся системным: ввод ловит невидимое `TextField` поверх строки,
/// поэтому работают вставка, удаление и автоповтор клавиши.
struct MorphingNumberField: View {
    /// Уже сгруппированная строка («1 200 000»): группировку делает
    /// `NumberFormat.groupedInput` на стороне владельца.
    @Binding var text: String
    /// Единица после числа — «₽» или «км».
    let suffix: String
    var focused: FocusState<Bool>.Binding

    /// Мигающая палочка курсора: без неё пустое поле выглядит неживым.
    @State private var caretVisible = true

    private var symbols: [Character] { Array(text.isEmpty ? "0" : text) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                Text(String(symbol))
                    .font(.system(size: 40, weight: .bold).monospacedDigit())
                    .foregroundStyle(text.isEmpty ? Figma.labelsTertiary : .white)
                    // id по значению: иначе SwiftUI подменит строку молча,
                    // без перехода.
                    .id("\(index)-\(symbol)")
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }

            Text("\u{00A0}" + suffix)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(text.isEmpty ? Figma.labelsTertiary : .white)

            if focused.wrappedValue {
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: 40)
                    .padding(.leading, 4)
                    .opacity(caretVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                               value: caretVisible)
                    .onAppear { caretVisible.toggle() }
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.74), value: text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .focused(focused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .onTapGesture { focused.wrappedValue = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Значение")
        .accessibilityValue(text.isEmpty ? "не задано" : text + " " + suffix)
    }
}
