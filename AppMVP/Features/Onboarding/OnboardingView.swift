import AuthenticationServices
import SwiftUI

/// Онбординг Beepy — Figma «1 флоу: онбординг + добавление машины» (node 45822:3994).
/// Геометрия задана абсолютно, как в макете (frame 402×874), поэтому координаты
/// отсчитываются от верхнего края экрана, а не от safe area.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
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
            Group {
                if step == 0 {
                    welcome
                } else {
                    survey(pages[step - 1], index: step - 1)
                        .id(step)
                }
            }
            .transition(
                .asymmetric(
                    insertion: .move(edge: goingForward ? .trailing : .leading)
                        .combined(with: .opacity),
                    removal: .move(edge: goingForward ? .leading : .trailing)
                        .combined(with: .opacity)
                )
            )
        }
        .ignoresSafeArea()
        .animation(.interpolatingSpring(stiffness: 220, damping: 26), value: step)
    }

    // MARK: - онбординг/велком скрин (node 45822:3995)

    private var welcome: some View {
        // Content container: x = 41, ширина 338 (при frame 402 справа остаётся 23 — так в макете).
        ZStack(alignment: .topLeading) {
            title("Привет!")
                .figmaBlock(x: 41, width: 338, y: 528.75)

            description("Beepy — сервис, который поможет тебе держать всё самое важное \nдля автомобиля под контролем")
                .figmaBlock(x: 41, width: 338, y: 586.75)

            AppleSignInButton(onCompletion: handleAppleSignIn)
                .figmaBlock(x: 41, width: 338, y: 730.75)
        }
    }

    // MARK: - опрос/1…3

    private func survey(_ page: SurveyPage, index: Int) -> some View {
        // Form Container: x = 16, ширина 370. Заголовок 529.5, описание +96, кнопки +201.
        ZStack(alignment: .topLeading) {
            // Page Control: frame y = 61.5, h = 44; пилюля 24 по центру → 61.5 + 10
            PageIndicatorDots(count: pages.count, currentIndex: index)
                .frame(maxWidth: .infinity)
                .offset(y: 71.5)

            title(page.title)
                .figmaBlock(x: 16, width: 370, y: 529.5)

            description(page.description)
                .figmaBlock(x: 16, width: 370, y: 625.5)

            GlassProminentButton(title: page.primaryTitle, action: advance)
                .figmaBlock(x: 16, width: 370, y: 730.5)

            if page.hasSkip {
                GlassButton(title: "Пропустить", action: finish)
                    .figmaBlock(x: 16, width: 370, y: 796.5)
            }
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
