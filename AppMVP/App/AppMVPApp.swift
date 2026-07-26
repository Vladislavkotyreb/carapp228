import SwiftData
import SwiftUI

@main
struct AppMVPApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var metrics = DeviceMetrics()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(metrics)
                // Единственное место, где снимаются размеры экрана. Фон не
                // влияет на раскладку контента, а safe area здесь ещё настоящая.
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { metrics.update(size: geo.size, insets: geo.safeAreaInsets) }
                            .onChange(of: geo.size) { _, new in
                                metrics.update(size: new, insets: geo.safeAreaInsets)
                            }
                    }
                }
        }
        // Локальное хранилище на устройстве: данные машины и ТО никуда
        // не уходят, пока не появится сервер в РФ (docs/BACKEND.md).
        .modelContainer(for: [Car.self, ServiceRecord.self, ServiceWorkItem.self])
    }
}
