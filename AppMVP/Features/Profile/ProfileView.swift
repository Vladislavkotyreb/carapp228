import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ProfileContent(authService: appState.authService)
    }
}

private struct ProfileContent: View {
    @StateObject private var viewModel: ProfileViewModel

    init(authService: AuthService) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(authService: authService))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Аккаунт") {
                    LabeledContent("Email", value: viewModel.email)
                }

                Section {
                    Button(role: .destructive) {
                        Task { await viewModel.signOut() }
                    } label: {
                        Text("Выйти")
                    }
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(AppColors.danger)
                            .font(AppTypography.caption)
                    }
                }
            }
            .navigationTitle("Профиль")
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState())
}
