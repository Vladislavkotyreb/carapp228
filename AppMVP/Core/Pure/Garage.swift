import Foundation

/// Лимит относится только к машинам, найденным по госномеру.
/// Ручное добавление доступно при любом размере гаража.
enum Garage {
    static let plateCarLimit = 2
    static let limitMessage = "По\u{00A0}номеру можно добавить две машины. Добавьте по\u{00A0}названию."

    static func canAddByPlate(plateCarCount: Int, isOwnerBuild: Bool = false) -> Bool {
        isOwnerBuild || plateCarCount < plateCarLimit
    }
}
