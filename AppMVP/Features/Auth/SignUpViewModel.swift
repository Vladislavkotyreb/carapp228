import Foundation

@MainActor
final class SignUpViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var displayName = ""
    @Published var errorMessage: String?
    @Published var didSignUp = false

    let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    var canSubmit: Bool {
        !email.isEmpty &&
        password.count >= 6 &&
        password == confirmPassword &&
        !displayName.isEmpty
    }

    func signUp() async {
        errorMessage = nil
        guard password == confirmPassword else {
            errorMessage = "Пароли не совпадают"
            return
        }
        do {
            try await authService.signUp(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password,
                displayName: displayName.trimmingCharacters(in: .whitespaces)
            )
            didSignUp = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
