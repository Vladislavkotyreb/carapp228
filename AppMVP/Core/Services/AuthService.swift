import Foundation
import Supabase

enum AuthError: LocalizedError {
    case notConfigured
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Добавьте Config.plist с ключами Supabase. См. docs/SUPABASE_SETUP.md"
        case .unknown(let message):
            return message
        }
    }
}

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isLoading = false

    private var client: SupabaseClient { SupabaseService.shared.client }

    var isAuthenticated: Bool { session != nil }
    var userEmail: String? { session?.user.email }

    init() {
        Task { await restoreSession() }
    }

    func restoreSession() async {
        guard AppConfig.isConfigured else { return }
        do {
            session = try await client.auth.session
        } catch {
            session = nil
        }
    }

    func signIn(email: String, password: String) async throws {
        guard AppConfig.isConfigured else { throw AuthError.notConfigured }
        isLoading = true
        defer { isLoading = false }

        do {
            session = try await client.auth.signIn(email: email, password: password)
        } catch {
            throw AuthError.unknown(error.localizedDescription)
        }
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        guard AppConfig.isConfigured else { throw AuthError.notConfigured }
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await client.auth.signUp(
                email: email,
                password: password,
                data: ["display_name": .string(displayName)]
            )
            session = try await client.auth.session
        } catch {
            throw AuthError.unknown(error.localizedDescription)
        }
    }

    func signInWithApple(idToken: String, fullName: String?) async throws {
        guard AppConfig.isConfigured else { throw AuthError.notConfigured }
        isLoading = true
        defer { isLoading = false }

        do {
            session = try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken)
            )
            if let fullName {
                _ = try? await client.auth.update(user: UserAttributes(data: ["full_name": .string(fullName)]))
            }
        } catch {
            throw AuthError.unknown(error.localizedDescription)
        }
    }

    func signOut() async throws {
        guard AppConfig.isConfigured else { throw AuthError.notConfigured }
        try await client.auth.signOut()
        session = nil
    }
}
