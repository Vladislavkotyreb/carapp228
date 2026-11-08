import AuthenticationServices
import SwiftData
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    /// Маршрут зависит от того, есть ли машина в базе, а не от флага
    /// в UserDefaults — так состояние не может разъехаться с данными.
    @Query private var cars: [Car]

    var body: some View {
        Group {
            if appState.isCheckingAccount {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !appState.isSignedIn || !appState.hasCompletedOnboarding {
                OnboardingView()
            } else if cars.isEmpty {
                AddCarView()
            } else {
                CarMainView()
            }
        }
        .task { await appState.checkAppleAccount() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            repeat {
                do { try Trip.clearExpiredAddresses(in: modelContext) }
                catch { print("Address cache cleanup failed: \(error)") }
                do { try await Task.sleep(for: .seconds(3600)) }
                catch { return }
            } while !Task.isCancelled
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await appState.checkAppleAccount() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
            Task { await appState.checkAppleAccount() }
        }
        .alert("Данные удалены", isPresented: $appState.accountDeleted) {
            Button("Как отключить вход через Apple") {
                if let url = URL(string: "https://support.apple.com/102571") { openURL(url) }
            }
            Button("Готово", role: .cancel) { }
        } message: {
            Text("Машины, поездки и локальный аккаунт удалены. Доступ Beepy к Apple ID можно отозвать в настройках Apple ID.")
        }
        .animation(.easeInOut, value: appState.hasCompletedOnboarding)
        .animation(.easeInOut, value: cars.isEmpty)
        // Всё приложение — в тёмной теме (тёмная редакция макета, 05.09.2026).
        // Объявляется здесь, а не в CarMainView: онбординг и добавление
        // машины идут до появления главной, и без этого их статус-бар и
        // клавиатура оставались бы светлыми.
        .preferredColorScheme(.dark)
        // Акцент приложения белый (DECISIONS), а системный tint — синий:
        // он вылезал синими кольцами и обводками на системных элементах
        // (замечание пользователя про корзины в форме ТО). Глобальный tint
        // закрывает и те места, куда акцент не прописан руками.
        .tint(.white)
    }
}
