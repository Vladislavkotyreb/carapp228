import SwiftData
import SwiftUI
import YandexMapsMobile

@main
struct AppMVPApp: App {
    init() {
        // Ключ ставится один раз до первого обращения к MapKit, иначе
        // sharedInstance() бросает исключение. Пустой ключ не передаём:
        // раздел «Карта» в этом случае показывает объяснение.
        if MapKitKey.isConfigured {
            YMKMapKit.setApiKey(MapKitKey.value)
            YMKMapKit.setLocale("ru_RU")
        }
    }

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
        .modelContainer(for: [Car.self, ServiceRecord.self, ServiceWorkItem.self,
                             Place.self])
    }
}
