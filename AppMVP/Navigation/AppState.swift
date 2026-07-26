import Foundation

@MainActor
final class AppState: ObservableObject {
    private let onboardingKey = "hasCompletedOnboarding"
    private let carAddedKey = "hasAddedCar"

    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingKey) }
    }

    @Published var hasAddedCar: Bool {
        didSet { UserDefaults.standard.set(hasAddedCar, forKey: carAddedKey) }
    }

    @Published var authService = AuthService()

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
        hasAddedCar = UserDefaults.standard.bool(forKey: carAddedKey)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func completeCarAdding() {
        hasAddedCar = true
    }
}
