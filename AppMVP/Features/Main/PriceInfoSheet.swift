import SwiftUI

/// Шторка цены машины — открывается тапом по плитке «Цена авто» на главной.
/// Референс пользователя (гараж Т-Банка): крупная цена по центру, ниже —
/// карточка-объяснение «это средняя цена по объявлениям». Своего в подаче
/// два: тёмная тема приложения и карандаш рядом с ценой — правка своей цены
/// живёт прямо здесь, а не спрятана в тап по плитке.
struct PriceInfoSheet: View {
    /// Что правим. Шторка одна на цену и пробег: подача, ввод и объяснение
    /// у них одинаковые, различаются числа и подписи (просьба пользователя
    /// «менять пробег тем же боттом щитом»).
    enum Kind { case price, odometer }

    private static let shape = UnevenRoundedRectangle(
        topLeadingRadius: 34, bottomLeadingRadius: 58,
        bottomTrailingRadius: 58, topTrailingRadius: 34
    )

    var kind: Kind = .price
    /// Текущий пробег — для режима `.odometer`.
    var odometer: Int = 0
    /// Своя цена пользователя, если вводил, — она главнее рыночной.
    let ownPrice: Int?
    /// Средняя рыночная по объявлениям и число объявлений под ней.
    let marketPrice: Int?
    let marketOffers: Int?
    /// Сохранение значения; nil — пользователь стёр его.
    let onSave: (Int?) -> Void
    /// Вернуть рыночную оценку вместо своей цены (только для `.price`).
    var onResetToMarket: (() -> Void)?
    let onClose: () -> Void

    /// Режим ввода (нода 46261:4222): карандаш превращает шторку в поле
    /// с галочкой, объяснение остаётся внизу, над клавиатурой. Логика из
    /// макетов: правка живёт в самой шторке, системного алерта больше нет.
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool
    /// Подъём над клавиатурой (нода 46261:4222): лист встаёт на клавиатуру,
    /// нижние скругления на время ввода уходят — низ вплотную к ней.
    @State private var keyboardLift: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if editing {
                editField
                    .padding(.top, 32)
                    .padding(.horizontal, 24)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                priceBlock
                Spacer(minLength: 0)
            }

            explanation
                .padding(.horizontal, 16)
                .padding(.bottom, editing ? 12 : 24)
        }
        .padding(.top, 16)
        .frame(height: 420)
        .frame(maxWidth: .infinity)
        .liquidGlass(in: sheetShape, tint: Figma.sheetBackground) {
            sheetShape.fill(Figma.sheetBackground)
        }
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .overlay(alignment: .top) {
            Capsule()
                .fill(Figma.vibrantPrimary)
                .frame(width: 58, height: 4)
                .padding(.top, 5)
        }
        .padding(.horizontal, editing ? 0 : 6)
        .padding(.bottom, editing ? 0 : 6)
        .offset(y: -keyboardLift)
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillShowNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                as? CGRect else { return }
            withAnimation(.easeOut(duration: 0.25)) { keyboardLift = frame.height }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { keyboardLift = 0 }
        }
    }

    /// Форма листа: в покое скругление и снизу (58), при вводе низ прямой —
    /// он прижат к клавиатуре, как в макете.
    private var sheetShape: UnevenRoundedRectangle {
        editing
            ? UnevenRoundedRectangle(topLeadingRadius: 34, bottomLeadingRadius: 0,
                                     bottomTrailingRadius: 0, topTrailingRadius: 34)
            : Self.shape
    }

    // MARK: - Тулбар: заголовок и крестик, как у остальных шторок

    private var toolbar: some View {
        ZStack {
            Text(kind == .price ? "Цена авто" : "Пробег")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.43)
                .foregroundStyle(Figma.vibrantControlsPrimary)

            HStack {
                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .liquidGlass(in: Circle(), tint: Figma.sheetControl) {
                            Circle()
                                .fill(Figma.sheetControl)
                                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                        }
                        .contentShape(Circle())
                        .motionRim(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть")
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Цена с карандашом

    /// Что стоит крупно: своя цена главнее, без своей — рыночная с «≈»,
    /// без обеих — прочерк. Тот же приоритет, что у плитки на главной.
    private var priceBlock: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Text(headline)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    // Цифры перетекают, а не подменяются — нативный аналог
                    // текстового морфа (просьба про Torph-эффект на цене).
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.35), value: headline)

                Button {
                    draft = kind == .odometer
                        ? NumberFormat.grouped(odometer)
                        : ownPrice.map(NumberFormat.grouped) ?? ""
                    editing = true
                    focused = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Figma.fillsTertiary, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Изменить цену")
            }
            .padding(.horizontal, 32)

            HStack(spacing: 8) {
                Text(badge)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Figma.graysGray)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Figma.fillsQuaternary, in: Capsule())

                // Маленькая кнопка рядом с чипсом: вернуть оценку рынка
                // вместо своей цены. Видна, только когда есть что вернуть.
                if kind == .price, ownPrice != nil, marketPrice != nil,
                   let onResetToMarket {
                    Button(action: onResetToMarket) {
                        Text("вернуть рыночную")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Figma.labelsTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Figma.fillsQuaternary, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Вернуть рыночную цену")
                }
            }
        }
    }

    /// Режим ввода: крупное поле и галочка подтверждения (нода 46261:4260).
    /// Галочка белая, а не синяя из прототипа — акцент кнопок в приложении
    /// белый, решение зафиксировано в DECISIONS.
    private var editField: some View {
        HStack(spacing: 14) {
            // Цифры въезжают посимвольно и перестраиваются по разрядам —
            // тот же морф, что в номерной рамке (просьба пользователя).
            MorphingNumberField(
                text: Binding(get: { draft },
                              set: { draft = NumberFormat.groupedInput($0) }),
                suffix: kind == .price ? "₽" : "км",
                focused: $focused)

            Button {
                onSave(NumberFormat.digits(draft))
                editing = false
                focused = false
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.white))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Сохранить цену")
        }
    }

    private var headline: String {
        if kind == .odometer {
            return "\(NumberFormat.grouped(odometer))\u{00A0}км"
        }
        if let ownPrice {
            return "\(NumberFormat.grouped(ownPrice))\u{00A0}₽"
        } else if let marketPrice {
            return "≈\u{00A0}\(NumberFormat.grouped(marketPrice))\u{00A0}₽"
        } else {
            return "—"
        }
    }

    private var badge: String {
        if kind == .odometer { "текущий пробег" }
        else if ownPrice != nil { "ваша цена" }
        else if marketPrice != nil { "средняя по рынку" }
        else { "цены пока нет" }
    }

    // MARK: - Объяснение

    /// Карточка под ценой. Для рыночной — откуда взялось число; когда цена
    /// своя, а рыночная тоже известна, — рыночная упоминается здесь; без
    /// цен — что делать дальше.
    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(explanationTitle)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.43)
                .foregroundStyle(.white)

            Text(explanationDetail)
                .font(.system(size: 15))
                .figmaLineHeight(20, fontSize: 15)
                .foregroundStyle(Figma.graysGray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Figma.fillsQuaternary, in: RoundedRectangle(cornerRadius: 20))
    }

    private var explanationTitle: String {
        if kind == .odometer { return "Пробег вводите сами" }
        if ownPrice == nil, marketPrice != nil { return "Это средняя цена" }
        if ownPrice != nil { return "Это ваша цена" }
        return "Откуда берётся цена"
    }

    private var explanationDetail: String {
        if kind == .odometer {
            return "От пробега считается, когда пора на следующее ТО. "
                 + "Обновляйте его карандашом после поездок."
        }
        let offers = marketOffers.map { " \(NumberFormat.grouped($0))" } ?? ""
        if ownPrice == nil, marketPrice != nil {
            return "На основе\(offers) объявлений о продаже похожих авто. "
                 + "Своя цена вводится карандашом — она заменит среднюю."
        }
        if let ownPrice, ownPrice > 0 {
            if let marketPrice {
                return "Средняя по объявлениям о продаже похожих авто — "
                     + "≈\u{00A0}\(NumberFormat.grouped(marketPrice))\u{00A0}₽. "
                     + "Показывается ваша: она главнее."
            }
            return "Вы ввели её вручную. Изменить можно карандашом."
        }
        return "У машин, добавленных по номеру, считается средняя по "
             + "объявлениям о продаже похожих авто. Свою цену можно "
             + "ввести карандашом."
    }
}
