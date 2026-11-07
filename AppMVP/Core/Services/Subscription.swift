import StoreKit

/// Подписка «Beepy Плюс»: бесплатно — до двух машин (`Garage`), с подпиской —
/// сколько угодно (решение пользователя 23.10.2026). StoreKit 2: товары,
/// покупка, восстановление и статус живут здесь, экраны только показывают.
///
/// Товары заводятся в App Store Connect с этими же идентификаторами. Пока их
/// там нет, `Product.products` отвечает пусто и пейвол говорит «пока
/// недоступна». Проверить покупку без App Store Connect — `Beepy.storekit`:
/// его берут `SubscriptionTests`, а в Xcode — Edit Scheme → Run → Options →
/// StoreKit Configuration.
@MainActor
final class Subscription: ObservableObject {
    static let shared = Subscription()

    static let monthID = "com.vladislavkotyrev.appmvp.plus.month"
    static let yearID = "com.vladislavkotyrev.appmvp.plus.year"
    static let productIDs: Set<String> = [monthID, yearID]

    enum Outcome: Equatable {
        case purchased
        case cancelled
        /// Ждёт подтверждения — например, «Попросить купить» в семье.
        case pending
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var offer: PaywallOffer = .loading
    @Published private(set) var isPremium = false

    private var updates: Task<Void, Never>?

    init() {
        // Продления, возвраты и покупки с другого устройства приходят сюда,
        // даже когда пейвол закрыт. Незавершённую транзакцию StoreKit
        // присылает снова при каждом запуске — поэтому `finish()`.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshStatus()
            }
        }
    }

    /// Товары и статус: при запуске и при каждом открытии пейвола.
    func load() async {
        if products.isEmpty { offer = .loading }
        do {
            // Дешёвый первым: месяц, потом год — порядок карточек не зависит
            // от того, в каком порядке ответил магазин.
            products = try await Product.products(for: Self.productIDs).sorted { $0.price < $1.price }
            offer = products.isEmpty ? .unavailable : .ready
        } catch {
            offer = .unavailable
        }
        await refreshStatus()
    }

    /// Есть ли действующая подписка. Истёкшие и отозванные StoreKit в
    /// `currentEntitlements` не кладёт; отзыв всё равно проверяем явно.
    func refreshStatus() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        isPremium = active
    }

    func purchase(_ product: Product) async throws -> Outcome {
        switch try await product.purchase() {
        case .success(let verification):
            // Неподтверждённая подпись — не покупка: подписку не включаем.
            guard case .verified(let transaction) = verification else { throw UnverifiedPurchase() }
            await transaction.finish()
            await refreshStatus()
            return .purchased
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }

    /// «Восстановить покупки» — App Store требует эту кнопку на пейволе.
    func restore() async throws {
        // Полное имя: `AppStore` в проекте — своя база SwiftData.
        try await StoreKit.AppStore.sync()
        await refreshStatus()
    }

    /// Срок тарифа для подписей. Неизвестный срок — как месяц: других у
    /// Beepy нет.
    static func period(of product: Product) -> PlanPeriod {
        product.subscription?.subscriptionPeriod.unit == .year ? .year : .month
    }

    /// Тарифы строками для пейвола: цена как отдал магазин, у годового —
    /// сколько это в месяц, в том же формате валюты.
    var plans: [PaywallPlan] {
        products.map { product in
            let period = Self.period(of: product)
            let perMonth = period == .year
                ? "≈\u{00A0}\((product.price / 12).formatted(product.priceFormatStyle)) \(PlanPeriod.month.per)"
                : nil
            return PaywallPlan(id: product.id, period: period, price: product.displayPrice, perMonth: perMonth)
        }
    }

    private struct UnverifiedPurchase: Error {}
}
