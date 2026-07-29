import CoreLocation
import SwiftUI
import YandexMapsMobile

/// Раздел «Карта». Дизайна на него в файле Figma нет, поэтому содержание
/// минимальное и согласованное отдельно: карта во весь экран и своя позиция.
struct MapScreen: View {
    @StateObject private var location = LocationPermission()

    var body: some View {
        Group {
            if MapKitKey.isConfigured {
                YandexMap()
            } else {
                missingKey
            }
        }
        .onAppear { location.request() }
    }

    /// Без ключа карта не рисуется вовсе. Показываем объяснение, а не пустой
    /// экран: иначе раздел выглядит сломанным, а не ненастроенным.
    private var missingKey: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Figma.vibrantSecondary)

            Text("Карта не настроена")
                .font(.system(size: 22, weight: .bold))
                .figmaLineHeight(28, fontSize: 22, weight: .bold)
                .foregroundStyle(Figma.labelsPrimary)

            Text("Добавьте ключ MapKit в MapKitKey.swift —\nбесплатно до 25 000 пользователей в месяц")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Figma.vibrantSecondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Figma.mainBackground)
    }
}

/// Разрешение на геопозицию. Само местоположение рисует слой MapKit, нам нужен
/// только системный запрос — поэтому менеджер и живёт отдельно от карты.
@MainActor
private final class LocationPermission: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    func request() {
        manager.delegate = self
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }
}

/// `YMKMapView` — вьюха UIKit, поэтому оборачиваем. Слой своей позиции
/// создаётся один раз при создании карты: пересоздание на каждом обновлении
/// вью роняет SDK.
private struct YandexMap: UIViewRepresentable {
    /// Контейнер, а не сама карта: инициализатор `YMKMapView` может вернуть
    /// nil (например, без доступного GPU), а тип вьюхи у представимого
    /// обязан быть неопциональным. Падать из-за этого нельзя.
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        guard let map = YMKMapView(frame: .zero) else { return container }

        map.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(map)
        NSLayoutConstraint.activate([
            map.topAnchor.constraint(equalTo: container.topAnchor),
            map.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            map.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            map.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        let layer = YMKMapKit.sharedInstance().createUserLocationLayer(with: map.mapWindow)
        layer.setVisibleWithOn(true)
        context.coordinator.userLocationLayer = layer
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Слой нужно удерживать: MapKit не владеет им сам, и без сильной ссылки
    /// метка позиции пропадает.
    final class Coordinator {
        var userLocationLayer: YMKUserLocationLayer?
    }
}
