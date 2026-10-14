import SwiftUI

/// Онбординг Beepy — Figma «1 флоу: онбординг + добавление машины» (node 45822:3994).
/// Верхние блоки стоят в координатах макета (frame 402×874) от верха экрана,
/// а кнопки прижаты к нижней safe area: в макете home indicator не нарисован,
/// и «Пропустить» заезжала на него даже на макетном устройстве.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var step = 0
    @State private var goingForward = true

    /// Страницы — то, что приложение умеет сейчас, а не макетный набор
    /// «любимые места / звуки / ТО» (просьба пользователя 15.10.2026).
    private let pages = SurveyPage.pages(plateLookup: VehicleLookupProvider.isAvailable)

    /// Иллюстрация страницы: между точками страниц (71.5 + 44) и заголовком
    /// (529.5) — с воздухом сверху и снизу.
    private enum Visual {
        static let top: CGFloat = 140
        static let height: CGFloat = 350
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Figma.backgroundsPrimary

            // Перелистывание: страница уезжает в сторону перехода, следующая
            // приходит с противоположной. Назад — зеркально.
            // Переход навешен на содержимое, а не на Group. Идентичность
            // меняется здесь же, на .id(step); когда .transition висел
            // снаружи, он отрабатывал только на смене ветки if/else, то есть
            // ровно на одном переходе из трёх — между страницами опроса
            // страница подменялась мгновенно.
            if step == 0 {
                welcome
                    .id(step)
                    .transition(pageTransition)
            } else {
                survey(pages[step - 1], index: step - 1)
                    .id(step)
                    .transition(pageTransition)
            }
        }
        .ignoresSafeArea()
        .animation(.interpolatingSpring(stiffness: 220, damping: 26), value: step)
    }

    /// Страница уезжает в сторону перехода, следующая приходит с
    /// противоположной. Назад из онбординга сейчас не ходят, но зеркальная
    /// ветка оставлена: кнопка «назад» появится вместе с шагами добавления.
    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: goingForward ? .trailing : .leading)
                .combined(with: .opacity),
            removal: .move(edge: goingForward ? .leading : .trailing)
                .combined(with: .opacity)
        )
    }

    // MARK: - онбординг/велком скрин (node 45822:3995)

    private var welcome: some View {
        // Content container (45822:3998): x = 32, ширина 338 — по 32 с каждой
        // стороны, блок ровно по центру.
        ZStack(alignment: .topLeading) {
            // Декоративная подложка из макета (45822:4013) снята: она была
            // светлым пятном под светлый фон, на чёрном читалась бы как блик.
            // Тёмного онбординга в прототипе нет — вернуть вместе с его нодой.
            // Пустая верхняя половина приветствия — место машины: та же
            // картинка, что у машины без кадра каталога на главной.
            Image("CarPhoto")
                .resizable()
                .scaledToFit()
                .frame(height: Visual.height)
                .modifier(OnboardingRise())
                .accessibilityHidden(true)
                .figmaBlock(x: 16, width: 370, y: Visual.top)

            title("Привет!")
                .modifier(OnboardingRise(delay: 0.15))
                .figmaBlock(x: 32, width: 338, y: 528.75)

            description("Beepy — сервис, который поможет тебе держать всё самое важное \nдля автомобиля под контролем")
                .modifier(OnboardingRise(delay: 0.25))
                .figmaBlock(x: 32, width: 338, y: 586.75)

            // На месте «Войти с Apple» из макета: входа нет, пока нет
            // аккаунтов и сервера, а кнопка входа, которая ничего не делает,
            // не проходит ревью App Store (решение пользователя 14.10.2026).
            GlassProminentButton(title: "Начать", action: advance)
                .figmaBlock(x: 32, width: 338, y: 730.75)
        }
    }

    // MARK: - опрос/1…3

    private func survey(_ page: SurveyPage, index: Int) -> some View {
        // Form Container: x = 16, ширина 370. Заголовок 529.5, описание +96, кнопки +201.
        ZStack(alignment: .topLeading) {
            // Декоративная подложка из макета (45822:4022) снята вместе с
            // тёмной темой — см. welcome.

            // Page Control: frame y = 61.5, h = 44; пилюля 24 по центру → 61.5 + 10
            PageIndicatorDots(count: pages.count, currentIndex: index)
                .frame(maxWidth: .infinity)
                .offset(y: 71.5)

            OnboardingVisual(feature: page.feature)
                .frame(height: Visual.height)
                .figmaBlock(x: 16, width: 370, y: Visual.top)

            title(page.title)
                .modifier(OnboardingRise(delay: 0.15))
                .figmaBlock(x: 16, width: 370, y: 529.5)

            description(page.description)
                .modifier(OnboardingRise(delay: 0.25))
                .figmaBlock(x: 16, width: 370, y: 625.5)

            // Кнопки стоят в координатах макета: первая на 730.5, вторая на
            // 796.5, зазор 12 (нода 45822:4058). Раньше они прижимались к
            // нижней safe area и из-за клампа поднимались на 21pt выше макета.
            // Слот «Пропустить» держится всегда, даже на последней странице,
            // иначе основная кнопка прыгала бы при перелистывании.
            VStack(spacing: 12) {
                GlassProminentButton(title: page.primaryTitle, action: advance)

                if page.hasSkip {
                    GlassButton(title: "Пропустить", action: finish)
                } else {
                    Color.clear.frame(height: 50)
                }
            }
            .figmaBlock(x: 16, width: 370, y: 730.5)
        }
    }

    // MARK: - Типографика макета

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Figma.titleSize, weight: .bold))
            .figmaLineHeight(Figma.titleLineHeight, fontSize: Figma.titleSize, weight: .bold)
            .foregroundStyle(Figma.labelsPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func description(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Figma.bodySize))
            .tracking(Figma.bodyTracking)
            .figmaLineHeight(Figma.bodyLineHeight, fontSize: Figma.bodySize)
            .foregroundStyle(Figma.graysGray)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Переходы

    private func advance() {
        goingForward = true
        if step < pages.count {
            step += 1
        } else {
            finish()
        }
    }

    private func finish() {
        appState.completeOnboarding()
    }
}

private struct SurveyPage {
    let feature: OnboardingFeature
    let title: String
    let description: String
    var primaryTitle = "Далее"
    var hasSkip = true

    /// «Машина по номеру» — только когда поиск есть: в выпуске без сервера
    /// страница обещала бы то, чего в приложении нет. Последняя страница —
    /// без «Пропустить» и с «Отлично, погнали!», какой бы она ни была.
    static func pages(plateLookup: Bool) -> [SurveyPage] {
        var pages = [
            SurveyPage(feature: .trips,
                       title: "Пробег считается сам",
                       description: "Beepy замечает поездку и\u{00A0}прибавляет километры. С\u{00A0}Bluetooth машины\u{00A0}— только твои поездки."),
            SurveyPage(feature: .sound,
                       title: "Слушай мотор",
                       description: "Запиши звук двигателя\u{00A0}— Beepy подскажет, на\u{00A0}что посмотреть. Разбор идёт прямо на\u{00A0}телефоне.",
                       primaryTitle: "Круто, а\u{00A0}что ещё?"),
            SurveyPage(feature: .service,
                       title: "ТО вовремя",
                       description: "Сколько осталось до\u{00A0}ТО, напоминание и\u{00A0}запись в\u{00A0}сервис рядом."),
        ]
        if plateLookup {
            pages.append(SurveyPage(feature: .plate,
                                    title: "Машина по\u{00A0}номеру",
                                    description: "Введи госномер\u{00A0}— марку, модель и\u{00A0}цену найдём сами."))
        }
        pages[pages.count - 1].primaryTitle = "Отлично, погнали!"
        pages[pages.count - 1].hasSkip = false
        return pages
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
