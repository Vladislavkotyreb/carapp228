import SwiftData
import SwiftUI

@main
struct AppMVPApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
        // Локальное хранилище на устройстве: данные машины и ТО никуда
        // не уходят, пока не появится сервер в РФ (docs/BACKEND.md).
        .modelContainer(for: [Car.self, ServiceRecord.self, ServiceWorkItem.self])
    }
}
