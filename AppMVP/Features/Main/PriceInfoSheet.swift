import SwiftUI

/// Шторка цены машины — открывается тапом по плитке «Цена авто» на главной.
/// Референс пользователя (гараж Т-Банка): крупная цена по центру, ниже —
/// карточка-объяснение «это средняя цена по объявлениям». Своего в подаче
/// два: тёмная тема приложения и карандаш рядом с ценой — правка своей цены
/// живёт прямо здесь, а не спрятана в тап по плитке.
struct PriceInfoSheet: View {
    private static let shape = UnevenRoundedRectangle(
        topLeadingRadius: 34, bottomLeadingRadius: 58,
        bottomTrailingRadius: 58, topTrailingRadius: 34
    )

    /// Своя цена пользователя, если вводил, — она главнее рыночной.
    let ownPrice: Int?
    /// Средняя рыночная по объявлениям и число объявлений под ней.
    let marketPrice: Int?
    let marketOffers: Int?
    /// Карандаш: закрыть шторку и открыть правку своей цены.
    let onEdit: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Spacer(minLength: 0)

            priceBlock

            Spacer(minLength: 0)

            explanation
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .padding(.top, 16)
        .frame(height: 420)
        .frame(maxWidth: .infinity)
        .liquidGlass(in: Self.shape, tint: Figma.sheetBackground) {
            Self.shape.fill(Figma.sheetBackground)
        }
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

    // MARK: - Тулбар: заголовок и крестик, как у остальных шторок

    private var toolbar: some View {
        ZStack {
            Text("Цена авто")
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

                Button(action: onEdit) {
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

            Text(badge)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Figma.graysGray)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Figma.fillsQuaternary, in: Capsule())
        }
    }

    private var headline: String {
        if let ownPrice {
            "\(NumberFormat.grouped(ownPrice))\u{00A0}₽"
        } else if let marketPrice {
            "≈\u{00A0}\(NumberFormat.grouped(marketPrice))\u{00A0}₽"
        } else {
            "—"
        }
    }

    private var badge: String {
        if ownPrice != nil { "ваша цена" }
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
        if ownPrice == nil, marketPrice != nil { return "Это средняя цена" }
        if ownPrice != nil { return "Это ваша цена" }
        return "Откуда берётся цена"
    }

    private var explanationDetail: String {
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
