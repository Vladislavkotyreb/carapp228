import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var errorMessage: String?

    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    var email: String {
        authService.userEmail ?? "—"
    }

    func signOut() async {
        errorMessage = nil
        do {
            try await authService.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
