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
    @State private var goingForward = true
    @State private var showDeleteConfirmation = false
    @State private var showLocationSettings = false
    @State private var requestingGPS = false

    private var title: String {
        switch step {
        case 0: VehicleLookupProvider.isAvailable ? "Машина\nпо номеру" : "Твоя машина.\nВсё под рукой."
        case 1: "Послушай,\nкак она работает"
        default: "Каждая поездка\nв твоей истории"
        }
    }

    private var detail: String {
        switch step {
        case 0: VehicleLookupProvider.isAvailable
            ? "Введи госномер — Beepy найдёт машину. Пробег, обслуживание и\u{00A0}поездки будут в\u{00A0}одном месте."
            : "Добавь машину по названию. Храни пробег, обслуживание и\u{00A0}поездки в\u{00A0}одном месте."
        case 1: "Запиши звук двигателя. Beepy проанализирует его на телефоне и\u{00A0}подскажет, что проверить у\u{00A0}механика."
        default: "Beepy заметит поездку и\u{00A0}сохранит маршрут и\u{00A0}километры. Для записи в\u{00A0}фоне разреши геопозицию «Всегда»."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button { go(to: step - 1) } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Назад")
                .accessibilityIdentifier("onboarding-back")
                .opacity(step == 0 ? 0 : 1)
                .disabled(step == 0)
                PageIndicatorDots(count: 3, currentIndex: step) { go(to: $0) }
            }
            .padding(.top, 8)
            .padding(.bottom, 12)

            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        OnboardingVisual(feature: [.plate, .sound, .trips][step])
                            .frame(height: max(180, min(330, geometry.size.height * 0.56)))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 16) {
                            Text(title)
                                .font(.system(size: 38, weight: .bold))
                                .tracking(-1.2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(detail)
                                .font(.system(size: 17))
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 16)
                    }
                    .frame(minHeight: geometry.size.height, alignment: .top)
                    .id(step)
                    .transition(pageTransition)
                }
                .scrollIndicators(.hidden)
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { gesture in
                    guard abs(gesture.translation.width) > abs(gesture.translation.height) * 1.4 else { return }
                    go(to: step + (gesture.translation.width < 0 ? 1 : -1))
                })
            }
            .clipped()
            .animation(reduceMotion ? Motion.fade : Motion.onboardingPage, value: step)

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
            .id(step)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
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

    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .offset(x: goingForward ? 24 : -24).combined(with: .opacity),
            removal: .offset(x: goingForward ? -16 : 16).combined(with: .opacity))
    }

    private func go(to index: Int) {
        guard appState.isSignedIn, (0..<3).contains(index), index != step else { return }
        goingForward = index > step
        step = index
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
