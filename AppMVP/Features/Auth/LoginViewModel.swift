import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var errorMessage: String?

    let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    var canSubmit: Bool {
        !email.isEmpty && password.count >= 6
    }

    func signIn() async {
        errorMessage = nil
        do {
            try await authService.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
