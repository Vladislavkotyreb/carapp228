import SwiftUI

struct SignUpView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SignUpContent(authService: appState.authService)
    }
}

private struct SignUpContent: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SignUpViewModel

    init(authService: AuthService) {
        _viewModel = StateObject(wrappedValue: SignUpViewModel(authService: authService))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text("Регистрация")
                    .font(AppTypography.largeTitle)

                AppTextField(title: "Имя", text: $viewModel.displayName, textContentType: .name)
                AppTextField(title: "Email", text: $viewModel.email, keyboardType: .emailAddress, textContentType: .emailAddress)
                AppTextField(title: "Пароль", text: $viewModel.password, isSecure: true, textContentType: .newPassword)
                AppTextField(title: "Повторите пароль", text: $viewModel.confirmPassword, isSecure: true, textContentType: .newPassword)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.danger)
                }

                PrimaryButton(
                    title: "Зарегистрироваться",
                    isLoading: viewModel.authService.isLoading,
                    isDisabled: !viewModel.canSubmit,
                    action: { Task { await viewModel.signUp() } }
                )
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.didSignUp) { _, signedUp in
            if signedUp { dismiss() }
        }
    }
}

#Preview {
    NavigationStack {
        SignUpView()
            .environmentObject(AppState())
    }
}
