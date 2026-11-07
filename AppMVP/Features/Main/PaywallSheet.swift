import SwiftUI

/// Пейвол подписки «Beepy Плюс». Открывается по «Добавить авто», когда машин
/// уже две, а подписки нет (`Garage.decide`, решение пользователя
/// 23.10.2026). Купили или восстановили — пейвол закрывается и открывается
/// форма добавления.
///
/// По правилам App Store (3.1.2) на экране: название подписки, срок и цена
/// каждого тарифа, условие автопродления, «Восстановить покупки», ссылки на
/// условия и политику конфиденциальности.
struct PaywallSheet: View {
    @ObservedObject var subscription: Subscription
    /// Подписка есть — можно добавлять машину.
    let onUnlocked: () -> Void
    let onClose: () -> Void

    @State private var selectedID: String?
    @State private var busy = false
    @State private var message: String?
    @State private var legal: LegalDocument?

    var body: some View {
        VStack(spacing: 0) {
            SheetBar(title: "Beepy Плюс", closeSide: .trailing, onClose: onClose)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                PaywallBody(offer: subscription.offer,
                            plans: subscription.plans,
                            selectedID: selectedID ?? defaultSelection,
                            busy: busy,
                            onSelect: { selectedID = $0 },
                            onBuy: buy,
                            onRestore: restore,
                            onRetry: { Task { await subscription.load() } },
                            onLegal: { legal = $0 },
                            onSkip: skipForDebug)
            }
        }
        // Чёрный, как главная: кадр машины под тканью нарисован на чёрном и
        // на сером фоне шторки читался прямоугольником.
        .background(Figma.backgroundsPrimary.ignoresSafeArea())
        .task { await subscription.load() }
        // Купили, восстановили или подписка пришла с другого устройства —
        // пейвол больше не нужен.
        .onChange(of: subscription.isPremium) { _, premium in
            if premium { onUnlocked() }
        }
        .sheet(item: $legal) { document in
            LegalSheet(document: document) { legal = nil }
        }
        .alert("Подписка", isPresented: Binding(get: { message != nil },
                                                set: { if !$0 { message = nil } })) {
            Button("Понятно", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    /// Год выгоднее — он выбран, пока человек не выбрал сам.
    private var defaultSelection: String? {
        subscription.products.first { $0.id == Subscription.yearID }?.id ?? subscription.products.first?.id
    }

    private func buy() {
        guard let id = selectedID ?? defaultSelection,
              let product = subscription.products.first(where: { $0.id == id }) else { return }
        busy = true
        Task {
            do {
                switch try await subscription.purchase(product) {
                case .purchased:
                    break   // пейвол закроет `onChange` по статусу
                case .pending:
                    message = "Покупка ждёт подтверждения\u{00A0}— подписка включится, когда оно придёт."
                case .cancelled:
                    break
                }
            } catch {
                message = "Не\u{00A0}получилось оформить подписку. Попробуйте ещё раз."
            }
            busy = false
        }
    }

    private func restore() {
        busy = true
        Task {
            do {
                try await subscription.restore()
                if !subscription.isPremium { message = "Действующей подписки не\u{00A0}нашлось." }
            } catch {
                message = "Не\u{00A0}получилось восстановить покупки. Проверьте интернет."
            }
            busy = false
        }
    }

    /// Только отладка: разработчик добавляет машины без подписки, видя при
    /// этом пейвол. В выпуске этой кнопки нет.
    private var skipForDebug: (() -> Void)? {
        #if DEBUG
        return onUnlocked
        #else
        return nil
        #endif
    }
}

/// Содержимое пейвола без прокрутки и шапки. Принимает строки тарифов, а не
/// товары StoreKit: его же рисует тест в картинку (`SubscriptionTests`) —
/// в симуляторе без App Store Connect до тарифов иначе не дойти.
struct PaywallBody: View {
    let offer: PaywallOffer
    let plans: [PaywallPlan]
    let selectedID: String?
    let busy: Bool
    let onSelect: (String) -> Void
    let onBuy: () -> Void
    let onRestore: () -> Void
    let onRetry: () -> Void
    let onLegal: (LegalDocument) -> Void
    var onSkip: (() -> Void)?

    private enum Layout {
        static let margin: CGFloat = 16
        static let heroHeight: CGFloat = 150
        static let planHeight: CGFloat = 72
        static let planRadius: CGFloat = 20
        static let button: CGFloat = 52
    }

    var body: some View {
        VStack(spacing: 24) {
            Image("CarPhoto")
                .resizable()
                .scaledToFit()
                .frame(height: Layout.heroHeight)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Третья машина\u{00A0}— с\u{00A0}Beepy\u{00A0}Плюс")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Figma.labelsPrimary)
                    .multilineTextAlignment(.center)
                Text("Бесплатно\u{00A0}— две машины. С\u{00A0}подпиской\u{00A0}— сколько угодно.")
                    .font(.system(size: 17))
                    .foregroundStyle(Figma.labelsSecondary)
                    .multilineTextAlignment(.center)
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                benefit("Сколько угодно машин в\u{00A0}гараже")
                benefit("ТО, поездки и\u{00A0}диагностика\u{00A0}— для каждой")
                benefit("Отменить можно в\u{00A0}любой момент")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            planList

            footer
        }
        .padding(.horizontal, Layout.margin)
        .padding(.bottom, 24)
    }

    private func benefit(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Figma.accentsGreen)
            Text(text)
                .font(.system(size: 17))
                .foregroundStyle(Figma.labelsPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Тарифы

    @ViewBuilder
    private var planList: some View {
        switch offer {
        case .loading where plans.isEmpty:
            ProgressView()
                .tint(Figma.labelsPrimary)
                .frame(maxWidth: .infinity, minHeight: Layout.planHeight * 2 + 12)
        case .unavailable where plans.isEmpty:
            VStack(spacing: 12) {
                Text("Подписка пока недоступна. Проверьте интернет и\u{00A0}попробуйте ещё раз.")
                    .font(.system(size: 15))
                    .foregroundStyle(Figma.graysGray)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Повторить", action: onRetry)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Figma.labelsPrimary)
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: Layout.planRadius))
        default:
            VStack(spacing: 12) {
                ForEach(plans) { plan in
                    planCard(plan)
                }
            }
        }
    }

    private func planCard(_ plan: PaywallPlan) -> some View {
        let selected = plan.id == selectedID
        return Button { onSelect(plan.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Figma.labelsPrimary : Figma.graysGray)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.period.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Figma.labelsPrimary)
                    if let perMonth = plan.perMonth {
                        Text(perMonth)
                            .font(.system(size: 13))
                            .foregroundStyle(Figma.graysGray)
                    }
                }
                Spacer(minLength: 8)
                Text("\(plan.price) \(plan.period.per)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Figma.labelsPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: Layout.planHeight)
            .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: Layout.planRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Layout.planRadius)
                    .strokeBorder(selected ? Figma.labelsPrimary : .clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: Layout.planRadius))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Покупка и правила

    private var selectedPlan: PaywallPlan? {
        plans.first { $0.id == selectedID }
    }

    private var footer: some View {
        VStack(spacing: 16) {
            if let plan = selectedPlan {
                // Своя белая кнопка, а не `GlassProminentButton`: тот рассчитан
                // на светлый фон онбординга (TRAPS).
                Button(action: onBuy) {
                    ZStack {
                        if busy {
                            ProgressView().tint(.black)
                        } else {
                            Text(PlanPeriod.cta(price: plan.price, period: plan.period))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.black)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: Layout.button)
                    .background(Figma.labelsPrimary, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }

            Text("Подписка продлевается автоматически, пока её не\u{00A0}отменить в\u{00A0}настройках Apple\u{00A0}ID не\u{00A0}позднее чем за\u{00A0}24\u{00A0}часа до\u{00A0}конца периода. Оплата\u{00A0}— с\u{00A0}аккаунта Apple\u{00A0}ID при подтверждении покупки.")
                .font(.system(size: 12))
                .foregroundStyle(Figma.graysGray)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                link("Восстановить", action: onRestore)
                link("Условия") { onLegal(.terms) }
                link("Конфиденциальность") { onLegal(.privacy) }
            }
            .disabled(busy)

            if let onSkip {
                Button("Добавить без подписки\u{00A0}— отладка", action: onSkip)
                    .font(.system(size: 13))
                    .foregroundStyle(Figma.graysGray)
                    .frame(minHeight: 44)
            }
        }
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Figma.labelsPrimary)
            .frame(minHeight: 44)
    }
}
