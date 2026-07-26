import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        LoginContent(authService: appState.authService)
    }
}

private struct LoginContent: View {
    @StateObject private var viewModel: LoginViewModel
    @State private var showSignUp = false

    init(authService: AuthService) {
        _viewModel = StateObject(wrappedValue: LoginViewModel(authService: authService))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Вход")
                            .font(AppTypography.largeTitle)
                        Text("Войдите, чтобы продолжить")
                            .foregroundStyle(AppColors.secondary)
                    }

                    if !AppConfig.isConfigured {
                        configBanner
                    }

                    AppTextField(title: "Email", text: $viewModel.email, keyboardType: .emailAddress, textContentType: .emailAddress)
                    AppTextField(title: "Пароль", text: $viewModel.password, isSecure: true, textContentType: .password)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.danger)
                    }

                    PrimaryButton(
                        title: "Войти",
                        isLoading: viewModel.authService.isLoading,
                        isDisabled: !viewModel.canSubmit,
                        action: { Task { await viewModel.signIn() } }
                    )

                    SecondaryButton(title: "Создать аккаунт") {
                        showSignUp = true
                    }
                }
                .padding(AppSpacing.lg)
            }
            .background(AppColors.background)
            .navigationDestination(isPresented: $showSignUp) {
                SignUpView()
            }
        }
    }

    private var configBanner: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Скопируйте Config.example.plist → Config.plist и добавьте ключи Supabase.")
                .font(AppTypography.caption)
        }
        .padding(AppSpacing.md)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

#Preview {
    LoginView()
        .environmentObject(AppState())
}
