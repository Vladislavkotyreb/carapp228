import SwiftUI

/// Figma: «Segmented Control» — 370×50, radius 100, фон Fills/Tertiary,
/// внутренний паддинг 2, гэп 4 между опциями. Выбранная опция — белая капсула
/// с тенью 0/2/10 rgba(0,0,0,0.06), лейбл Semibold; невыбранная — Medium.
struct FigmaSegmentedControl: View {
    let titles: [String]
    @Binding var selection: Int

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(titles.indices, id: \.self) { index in
                let isSelected = index == selection
                Button {
                    guard selection != index else { return }
                    withAnimation(Motion.selection) { selection = index }
                } label: {
                Text(titles[index])
                    .font(.system(size: 13.333, weight: isSelected ? .semibold : .medium))
                    .tracking(-0.08)
                    .foregroundStyle(Figma.labelsPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        // пилюля переезжает между сегментами, а не появляется заново
                        if isSelected {
                            Capsule()
                                .fill(.white)
                                .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
                                .matchedGeometryEffect(id: "segment", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(titles[index])
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .frame(height: 50)
        .background(Figma.fillsTertiary, in: Capsule())
        // HIG: смена сегмента — .selection, не impact
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Figma: «Text Field» — 52pt, radius 26, фон Fills/Tertiary, паддинг 16,
/// текст 17 Medium с трекингом −0.43.
struct FigmaTextField: View {
    let placeholder: String
    @Binding var text: String
    var placeholderColor: Color = Figma.labelsQuaternary
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 17, weight: .medium))
                    .tracking(-0.43)
                    .foregroundStyle(placeholderColor)
            }
            TextField("", text: $text)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Figma.labelsPrimary)
                .keyboardType(keyboardType)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: 26))
    }
}

/// Figma: сгруппированный «Text Field» — два поля по 52pt в одной капсуле radius 26
/// с разделителем Separators/Vibrant между ними.
struct FigmaGroupedTextField: View {
    let firstPlaceholder: String
    @Binding var first: String
    let secondPlaceholder: String
    @Binding var second: String
    var secondKeyboardType: UIKeyboardType = .default
    /// В базовом состоянии макета у группы снизу 19pt паддинга (высота 123),
    /// в состоянии с ошибкой его нет (высота 104).
    var bottomPadding: CGFloat = 19

    var body: some View {
        VStack(spacing: 0) {
            row(firstPlaceholder, text: $first)

            Rectangle()
                .fill(Figma.separatorsVibrant)
                .frame(height: 1)
                .padding(.leading, 16)

            row(secondPlaceholder, text: $second, keyboardType: secondKeyboardType)
        }
        .padding(.bottom, bottomPadding)
        .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: 26))
    }

    private func row(_ placeholder: String, text: Binding<String>,
                     keyboardType: UIKeyboardType = .default) -> some View {
        ZStack(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 17, weight: .medium))
                    .tracking(-0.43)
                    .foregroundStyle(Figma.labelsTertiary)
            }
            TextField("", text: text)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Figma.labelsPrimary)
                .keyboardType(keyboardType)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
}

/// Figma: «Row - Button» — 52pt, radius 26, фон Fills/Tertiary,
/// лейбл 17 Regular цветом Accents/Blue с иконкой.
struct FigmaRowLabel: View {
    let systemImage: String
    let title: String

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: systemImage)
            Text("  \(title) ")
        }
        .font(.system(size: 17))
        .tracking(-0.43)
        .foregroundStyle(Figma.accentsBlue)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: 26))
    }
}

/// Тряска инпута — по аннотации в макете: «хаптик негативное действие и тряска инпута».
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(animatableData * .pi * 4) * 8, y: 0))
    }
}

extension View {
    func shake(_ trigger: CGFloat) -> some View {
        modifier(ShakeEffect(animatableData: trigger))
    }
}
