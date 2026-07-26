import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HomeContent(authService: appState.authService)
    }
}

private struct HomeContent: View {
    @StateObject private var viewModel: HomeViewModel

    init(authService: AuthService) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(authService: authService))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .loading:
                    ProgressView("Загрузка…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    emptyState
                case .error(let message):
                    errorState(message)
                case .content(let items):
                    listContent(items)
                }
            }
            .navigationTitle("Главная")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                addItemBar
            }
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
        }
    }

    private var addItemBar: some View {
        HStack(spacing: AppSpacing.sm) {
            TextField("Новый элемент", text: $viewModel.newItemTitle)
                .padding(AppSpacing.md)
                .background(AppColors.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))

            Button {
                Task { await viewModel.addItem() }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .disabled(viewModel.newItemTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(AppSpacing.md)
        .background(.ultraThinMaterial)
    }

    private func listContent(_ items: [AppItem]) -> some View {
        List(items) { item in
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(item.title)
                    .font(AppTypography.title)
                if let date = item.createdAt {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondary)
                }
            }
            .padding(.vertical, AppSpacing.xs)
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Пока пусто",
            systemImage: "tray",
            description: Text("Добавьте первый элемент внизу экрана")
        )
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Ошибка", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Повторить") {
                Task { await viewModel.load() }
            }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
}
