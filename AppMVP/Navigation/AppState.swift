import Foundation

@MainActor
final class AppState: ObservableObject {
    private let onboardingKey = "hasCompletedOnboarding"

    /// Пройден ли онбординг. Это не персональные данные, поэтому остаётся
    /// в UserDefaults; всё, что относится к машине, лежит в SwiftData.
    /// Флага `hasAddedCar` больше нет — наличие машины выводится из базы,
    /// иначе флаг и данные разъезжаются.
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingKey) }
    }

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}
