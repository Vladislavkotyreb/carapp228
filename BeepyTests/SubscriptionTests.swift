import StoreKitTest
import SwiftUI
import XCTest
@testable import Beepy

/// Подписка «Beepy Плюс» без App Store Connect: товары, покупка и истечение
/// из `Beepy.storekit` в корне репозитория через `SKTestSession`. Файл
/// берётся по пути исходника теста — симулятор читает файлы мака, и копия в
/// бандле не нужна.
///
/// `xcodebuild test` на симуляторах iOS 26.5 и 27.0 тестовый StoreKit не
/// включает: товаров ноль, запросы уходят в песочницу Apple (проверено
/// 23.10.2026, известная проблема инструментов — TRAPS). Тогда тесты
/// покупки пропускаются с объяснением; из Xcode (⌘U) они идут.
@MainActor
final class SubscriptionTests: XCTestCase {
    private var session: SKTestSession!

    override func setUp() async throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Beepy.storekit")
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    /// Подписка с товарами из конфигурации — или пропуск, если тестовый
    /// StoreKit в этом окружении не включился.
    private func loadedSubscription() async throws -> Subscription {
        let subscription = Subscription()
        await subscription.load()
        if subscription.products.isEmpty {
            throw XCTSkip("тестовый StoreKit не отдал товаров — xcodebuild на iOS 26.5/27.0; запустите из Xcode (⌘U)")
        }
        return subscription
    }

    func testProductsLoadFromConfiguration() async throws {
        let subscription = try await loadedSubscription()
        XCTAssertEqual(subscription.offer, .ready)
        XCTAssertEqual(Set(subscription.products.map(\.id)), Subscription.productIDs)
        XCTAssertEqual(subscription.products.first?.id, Subscription.monthID, "месяц — первым, он дешевле")
        XCTAssertFalse(subscription.isPremium)
    }

    /// Две машины без подписки — пейвол; купили год — третью можно.
    func testPurchaseUnlocksThirdCar() async throws {
        let subscription = try await loadedSubscription()
        XCTAssertEqual(Garage.decide(carCount: 2, isPremium: subscription.isPremium), .paywall)

        let year = try XCTUnwrap(subscription.products.first { $0.id == Subscription.yearID })
        let outcome = try await subscription.purchase(year)
        XCTAssertEqual(outcome, .purchased)
        XCTAssertTrue(subscription.isPremium)
        XCTAssertEqual(Garage.decide(carCount: 2, isPremium: subscription.isPremium), .add)
    }

    /// Подписка кончилась — лимит снова действует.
    func testExpiredSubscriptionLocksAgain() async throws {
        let subscription = try await loadedSubscription()
        let month = try XCTUnwrap(subscription.products.first { $0.id == Subscription.monthID })
        _ = try await subscription.purchase(month)
        XCTAssertTrue(subscription.isPremium)

        try session.expireSubscription(productIdentifier: Subscription.monthID)
        await subscription.refreshStatus()
        XCTAssertFalse(subscription.isPremium)
    }

    /// Пейвол с тарифами — картинкой, чтобы увидеть экран, до которого в
    /// симуляторе без App Store Connect не дойти. Цены — как в
    /// `Beepy.storekit`. Только по запросу:
    /// `TEST_RUNNER_BEEPY_SNAPSHOT_DIR=<папка> xcodebuild test …`.
    func testPaywallSnapshot() throws {
        guard let dir = ProcessInfo.processInfo.environment["BEEPY_SNAPSHOT_DIR"] else {
            throw XCTSkip("снимок пейвола — по запросу")
        }
        let plans = [
            PaywallPlan(id: Subscription.monthID, period: .month, price: "199,00\u{00A0}₽", perMonth: nil),
            PaywallPlan(id: Subscription.yearID, period: .year, price: "1\u{00A0}490,00\u{00A0}₽",
                        perMonth: "≈\u{00A0}124,17\u{00A0}₽ в\u{00A0}месяц"),
        ]
        let view = PaywallBody(offer: .ready,
                               plans: plans,
                               selectedID: Subscription.yearID,
                               busy: false,
                               onSelect: { _ in }, onBuy: {}, onRestore: {}, onRetry: {},
                               onLegal: { _ in }, onSkip: {})
            .frame(width: 402)
            .background(Figma.backgroundsPrimary)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let data = try XCTUnwrap(renderer.uiImage?.pngData())
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("paywall.png"))
    }
}
