import Foundation

struct UserProfile: Codable, Identifiable, Sendable {
    let id: UUID
    var displayName: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}

struct AppItem: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let userId: UUID
    var title: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case createdAt = "created_at"
    }
}

struct NewAppItem: Encodable, Sendable {
    let userId: UUID
    let title: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case title
    }
}
