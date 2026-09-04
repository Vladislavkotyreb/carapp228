import SwiftData
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    /// Маршрут зависит от того, есть ли машина в базе, а не от флага
    /// в UserDefaults — так состояние не может разъехаться с данными.
    @Query private var cars: [Car]

    var body: some View {
        Group {
            if !appState.hasCompletedOnboarding {
                OnboardingView()
            } else if cars.isEmpty {
                AddCarView()
            } else {
                CarMainView()
            }
        }
        .animation(.easeInOut, value: appState.hasCompletedOnboarding)
        .animation(.easeInOut, value: cars.isEmpty)
        // Всё приложение — в тёмной теме (тёмная редакция макета, 05.09.2026).
        // Объявляется здесь, а не в CarMainView: онбординг и добавление
        // машины идут до появления главной, и без этого их статус-бар и
        // клавиатура оставались бы светлыми.
        .preferredColorScheme(.dark)
    }
}
