import Foundation

enum HomeViewState: Equatable {
    case loading
    case content([AppItem])
    case empty
    case error(String)
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var state: HomeViewState = .loading
    @Published var newItemTitle = ""

    private let itemsService = ItemsService.shared
    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    func load() async {
        state = .loading
        do {
            let items = try await itemsService.fetchItems()
            state = items.isEmpty ? .empty : .content(items)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func addItem() async {
        let title = newItemTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let userId = authService.session?.user.id else { return }
        do {
            _ = try await itemsService.addItem(title: title, userId: userId)
            newItemTitle = ""
            await load()
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
