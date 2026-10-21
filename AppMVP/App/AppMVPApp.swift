import SwiftData
import SwiftUI
import UserNotifications
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
            // Порядок из документации Яндекса: инстанс создаётся сразу за
            // ключом. И раз инициализация идёт не в
            // `didFinishLaunchingWithOptions`, а в `init` структуры App,
            // документация требует дополнительно поднять MapKit вручную —
            // сам он этого не сделает.
            YMKMapKit.sharedInstance().onStart()
        }
        // Автоопределение поездок слушает сигналы системы — выход из зоны,
        // значимое перемещение. Ради них система запускает приложение в фоне,
        // и принять сигнал должен уже готовый трекер: окна в этот момент нет.
        // Баннеры «Поездка началась» и напоминания о ТО — и при открытом
        // приложении: без делегата система их на переднем плане глотает.
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        _ = TripTracker.shared
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
                    // Метрики описывают экран, а не клавиатуру: без этого её
                    // подъём раздувал нижний inset, контейнеры экранов
                    // сжимались и кнопки «прилипали» к верху клавиатуры.
                    .ignoresSafeArea(.keyboard)
                }
        }
        // Локальное хранилище на устройстве: данные машины и ТО никуда
        // не уходят, пока не появится сервер в РФ (docs/BACKEND.md).
        // Контейнер общий с действиями «Команд» (`AppStore`): автопробег
        // пишет в ту же базу, когда окна приложения нет.
        .modelContainer(AppStore.container)
    }
}
