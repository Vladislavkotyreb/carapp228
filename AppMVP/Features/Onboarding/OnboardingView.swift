import AuthenticationServices
import SwiftUI

/// Онбординг Beepy — Figma «1 флоу: онбординг + добавление машины» (node 45822:3994).
/// Верхние блоки стоят в координатах макета (frame 402×874) от верха экрана,
/// а кнопки прижаты к нижней safe area: в макете home indicator не нарисован,
/// и «Пропустить» заезжала на него даже на макетном устройстве.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var metrics: DeviceMetrics
    @State private var step = 0
    @State private var goingForward = true

    private let pages: [SurveyPage] = [
        // опрос/1 — node 45822:4018
        SurveyPage(
            title: "Отмечай любимые места ",
            description: "Заправки, автомойки, СТО.\nПоможем сохрнать любимое место \nне только в памяти, но и на карте",
            primaryTitle: "Далее",
            hasSkip: true
        ),
        // опрос/2 — node 45825:2235
        SurveyPage(
            title: "Следи за звуками\nиз машины",
            description: "Любой стук, гул теперь под контролем. \nПодскажем возможные причины \nпри помощи ИИ.",
            primaryTitle: "Круто, а что ещё есть?",
            hasSkip: true
        ),
        // опрос/3 — node 45826:2283
        SurveyPage(
            title: "Записывай \nрезультаты ТО",
            description: "Записывай пробег, работы и сканируй документы. А мы подскажем дату следующего ТО.",
            primaryTitle: "Отлично, погнали!",
            hasSkip: false
        )
    ]

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
            title("Привет!")
                .figmaBlock(x: 32, width: 338, y: 528.75)

            description("Beepy — сервис, который поможет тебе держать всё самое важное \nдля автомобиля под контролем")
                .figmaBlock(x: 32, width: 338, y: 586.75)

            AppleSignInButton(onCompletion: handleAppleSignIn)
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

            title(page.title)
                .figmaBlock(x: 16, width: 370, y: 529.5)

            description(page.description)
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

    /// Аккаунта пока нет: данные лежат локально на устройстве, поэтому вход
    /// ничего не даёт и флоу просто продолжается. Привязка Apple ID появится
    /// вместе с сервером — см. docs/BACKEND.md.
    private func handleAppleSignIn(_ result: Result<ASAuthorizationAppleIDCredential, Error>) {
        // TODO: при переходе на сервер — отправлять credential.identityToken
        // на бэкенд для проверки и заводить учётную запись.
        advance()
    }

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
    let title: String
    let description: String
    let primaryTitle: String
    let hasSkip: Bool
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
