import Foundation
import Supabase

enum ItemsError: LocalizedError {
    case notAuthenticated
    case notConfigured
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Войдите в аккаунт"
        case .notConfigured: return "Supabase не настроен"
        case .unknown(let message): return message
        }
    }
}

@MainActor
final class ItemsService {
    static let shared = ItemsService()
    private var client: SupabaseClient { SupabaseService.shared.client }

    func fetchItems() async throws -> [AppItem] {
        guard AppConfig.isConfigured else { throw ItemsError.notConfigured }
        return try await client
            .from("items")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func addItem(title: String, userId: UUID) async throws -> AppItem {
        guard AppConfig.isConfigured else { throw ItemsError.notConfigured }
        let payload = NewAppItem(userId: userId, title: title)
        return try await client
            .from("items")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }
}
