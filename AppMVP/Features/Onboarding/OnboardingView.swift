import AuthenticationServices
import SwiftData
import SwiftUI

/// Три шага: машина, звук двигателя, добровольное включение поездок.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @ObservedObject private var tracker = TripTracker.shared
    @State private var step = 0
    @State private var showDeleteConfirmation = false
    @State private var showLocationSettings = false
    @State private var requestingGPS = false

    private func title(for page: Int) -> String {
        switch page {
        case 0: VehicleLookupProvider.isAvailable ? "Машина\nпо номеру" : "Твоя машина.\nВсё под рукой."
        case 1: "Послушай,\nкак она работает"
        default: "Каждая поездка\nв твоей истории"
        }
    }

    private func detail(for page: Int) -> String {
        switch page {
        case 0: VehicleLookupProvider.isAvailable
            ? "Введи госномер — Beepy найдёт машину. Пробег, обслуживание и\u{00A0}поездки будут в\u{00A0}одном месте."
            : "Добавь машину по названию. Храни пробег, обслуживание и\u{00A0}поездки в\u{00A0}одном месте."
        case 1: "Запиши звук двигателя. Beepy проанализирует его на телефоне и\u{00A0}подскажет, что проверить у\u{00A0}механика."
        default: "Beepy заметит поездку и\u{00A0}сохранит маршрут и\u{00A0}километры. Для записи в\u{00A0}фоне разреши геопозицию «Всегда»."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { go(to: step - 1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Назад")
                .accessibilityIdentifier("onboarding-back")
                .opacity(step == 0 ? 0 : 1)
                .disabled(step == 0)
                Spacer()
            }
            .padding(.horizontal, OnboardingLayout.margin)

            TabView(selection: $step) {
                ForEach(0..<3) { page in
                    GeometryReader { geometry in
                        ScrollView {
                            VStack(spacing: OnboardingLayout.sectionGap) {
                                OnboardingVisual(feature: [.plate, .sound, .trips][page], isActive: page == step)
                                    .frame(width: min(OnboardingLayout.artWidth, geometry.size.width - 2 * OnboardingLayout.margin),
                                           height: min(OnboardingLayout.artHeight, geometry.size.height * 0.46))
                                    .accessibilityHidden(true)
                                VStack(spacing: OnboardingLayout.textGap) {
                                    Text(title(for: page))
                                        .font(.system(size: OnboardingLayout.titleSize, weight: .bold))
                                        .tracking(-0.7)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(detail(for: page))
                                        .font(.system(size: OnboardingLayout.bodySize))
                                        .foregroundStyle(.secondary)
                                        .lineSpacing(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: OnboardingLayout.copyWidth)
                            }
                            .padding(.horizontal, OnboardingLayout.margin)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: max(0, geometry.size.height - OnboardingLayout.indexSpace))
                            .padding(.bottom, OnboardingLayout.indexSpace)
                        }
                        .scrollIndicators(.hidden)
                    }
                    .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .never))

            VStack(spacing: 8) {
                if !appState.isSignedIn {
                    SignInWithAppleButton(.signIn,
                                          onRequest: appState.prepareAppleSignIn,
                                          onCompletion: appState.completeAppleSignIn)
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 54)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("apple-sign-in")
                        .disabled(appState.isDeletingAccount)
                } else {
                    GlassProminentButton(title: step == 2 ? "Включить GPS" : "Далее") {
                        if step == 2 { enableGPS() } else { go(to: step + 1) }
                    }
                    .accessibilityIdentifier("onboarding-next")
                }
                if step == 2 && appState.isSignedIn {
                    GlassButton(title: "Позже", action: finish)
                        .accessibilityIdentifier("onboarding-later")
                } else if !appState.isSignedIn && appState.hasLocalAccount {
                    Button("Удалить локальные данные", role: .destructive) { showDeleteConfirmation = true }
                        .frame(height: 50)
                } else {
                    Color.clear.frame(height: 50).accessibilityHidden(true)
                }
            }
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .padding(.horizontal, OnboardingLayout.margin)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .foregroundStyle(.white)
        .background(Figma.backgroundsPrimary.ignoresSafeArea())
        .onChange(of: tracker.access) { _, access in
            guard requestingGPS else { return }
            if access == .always || access == .whenInUse {
                requestingGPS = false
                tracker.setAuto(true)
                finish()
            } else if access == .denied {
                requestingGPS = false
                tracker.setAuto(false)
                showLocationSettings = true
            }
        }
        .alert("Геопозиция выключена", isPresented: $showLocationSettings) {
            Button("Открыть настройки") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Позже", role: .cancel, action: finish)
        } message: { Text("Разреши доступ к геопозиции в\u{00A0}настройках iPhone или продолжи без записи поездок.") }
        .alert("Вход через Apple", isPresented: Binding(
            get: { appState.accountError != nil },
            set: { if !$0 { appState.accountError = nil } }
        )) { Button("Понятно", role: .cancel) { appState.accountError = nil } }
        message: { Text(appState.accountError ?? "") }
        .confirmationDialog("Удалить аккаунт и\u{00A0}все данные Beepy на этом устройстве?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить аккаунт и\u{00A0}данные", role: .destructive) {
                Task { await appState.deleteLocalAccount(in: modelContext) }
            }
        } message: { Text("Будут удалены машины, поездки, история ТО и\u{00A0}избранные места.") }
    }

    private func go(to index: Int) {
        guard (0..<3).contains(index), index != step else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { step = index }
    }

    private func enableGPS() {
        guard tracker.access != .denied else { showLocationSettings = true; return }
        if tracker.access == .notAsked {
            requestingGPS = true
            tracker.requestAccess()
        } else {
            tracker.setAuto(true)
            if tracker.access == .whenInUse { tracker.requestAccess() }
            finish()
        }
    }

    private func finish() {
        guard appState.isSignedIn else { return }
        appState.completeOnboarding()
    }
}
