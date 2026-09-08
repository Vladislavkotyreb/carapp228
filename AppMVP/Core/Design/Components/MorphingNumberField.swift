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

    /// Строка целиком, с единицей: так «₽» не отрывается переносом.
    private var display: String { (text.isEmpty ? "0" : text) + "\u{00A0}" + suffix }

    var body: some View {
        HStack(spacing: 0) {
            // Одна строка с системным морфом цифр вместо стопки отдельных
            // символов: посимвольная сборка не умела ужиматься (длинная
            // цена выпихивала «₽» на вторую строку — баг с телефона) и
            // анимировала десяток вью на каждое нажатие, отсюда лаги.
            Text(display)
                .font(.system(size: 40, weight: .bold).monospacedDigit())
                .foregroundStyle(text.isEmpty ? Figma.labelsTertiary : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.28), value: text)

            if focused.wrappedValue {
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: 38)
                    .padding(.leading, 6)
                    .opacity(caretVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                               value: caretVisible)
                    .onAppear { caretVisible = false }
            }
        }
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
