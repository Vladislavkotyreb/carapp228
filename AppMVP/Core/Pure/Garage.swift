import Foundation

/// Сколько машин можно добавить без подписки (решение пользователя
/// 23.10.2026): две бесплатно, третья и дальше — с подпиской «Beepy Плюс».
/// Добавлять может каждый, лимит не прячет кнопку: на третьей машине вместо
/// формы открывается пейвол (`PaywallSheet`). Аккаунтов нет, так что
/// «пользователь» — это установка: правило считает машины в её базе.
///
/// Уже добавленные машины не трогаются — правило решает только, что
/// открыть по «Добавить авто».
enum Garage {
    static let freeCars = 2

    enum AddDecision: Equatable {
        /// Форма добавления.
        case add
        /// Пейвол подписки.
        case paywall
    }

    /// Что открыть по «Добавить авто» при стольких машинах.
    static func decide(carCount: Int, isPremium: Bool) -> AddDecision {
        isPremium || carCount < freeCars ? .add : .paywall
    }
}

/// Срок тарифа подписки — для подписей на пейволе. Отдельно от StoreKit:
/// `Product.SubscriptionPeriod` в чистый слой не заходит, экран переводит.
enum PlanPeriod: Equatable {
    case month
    case year

    var title: String {
        switch self {
        case .month: "Месяц"
        case .year: "Год"
        }
    }

    /// «в месяц» — после цены, неразрывно с ней.
    var per: String {
        switch self {
        case .month: "в\u{00A0}месяц"
        case .year: "в\u{00A0}год"
        }
    }

    /// Кнопка покупки: цена и срок на самой кнопке — App Store требует,
    /// чтобы человек видел, за что платит, до нажатия.
    static func cta(price: String, period: PlanPeriod) -> String {
        "Оформить за\u{00A0}\(price) \(period.per)"
    }
}

/// Тариф на пейволе — готовые строки, без StoreKit: экран и тест-снимок
/// рисуют его одинаково, а компонент не знает про `Product`.
struct PaywallPlan: Identifiable, Equatable {
    let id: String
    let period: PlanPeriod
    /// «199,00 ₽» — как отдал магазин, в валюте и формате человека.
    let price: String
    /// У годового — «≈ 124,17 ₽ в месяц»: то, ради чего выбирают год.
    let perMonth: String?
}

/// Что с тарифами: грузятся, есть или их нет вовсе (App Store Connect не
/// настроен, нет сети, покупки недоступны в регионе).
enum PaywallOffer: Equatable {
    case loading
    case ready
    case unavailable
}
