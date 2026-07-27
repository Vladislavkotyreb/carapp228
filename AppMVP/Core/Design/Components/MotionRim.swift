import CoreMotion
import SwiftUI

/// Наклон устройства для блика на кромке стеклянных поверхностей.
///
/// Системного API для этого нет: у `SwiftUICore.Glass` есть только `regular`,
/// `clear`, `identity`, `tint(_:)` и `interactive(_:)`, у `UIGlassEffect` в
/// UIKit — `interactive` и `tintColor`. Реактивную кромку, которая видна в
/// приложениях Apple, наружу не отдают, поэтому считаем угол сами.
@MainActor
final class DeviceTilt: ObservableObject {
    static let shared = DeviceTilt()

    /// Положение покоя: с него начинаем и к нему же приравниваем угол при
    /// Reduce Motion. Блик отсчитывает качание именно от него, поэтому в покое
    /// пятна стоят ровно в углах.
    static let neutralAngle: Double = -.pi / 2

    /// Направление «источника света» в системе координат экрана, радианы.
    @Published private(set) var angle: Double = DeviceTilt.neutralAngle

    private let manager = CMMotionManager()
    /// Сколько бликов сейчас на экране. Гироскоп работает только пока есть хоть один.
    private var subscribers = 0

    private var isDisabled: Bool {
        !manager.isDeviceMotionAvailable || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private init() {}

    func subscribe() {
        subscribers += 1
        guard subscribers == 1, !isDisabled else { return }

        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            // Крен и тангаж задают, с какой стороны «падает свет».
            let attitude = motion.attitude
            self?.angle = atan2(-attitude.pitch, attitude.roll) - .pi / 2
        }
    }

    func unsubscribe() {
        subscribers = max(0, subscribers - 1)
        if subscribers == 0 {
            manager.stopDeviceMotionUpdates()
        }
    }
}

/// Насколько далеко пятно блика уходит от своего угла. Вне вьюхи: она
/// генерик, а генерики не держат статических хранимых свойств.
private let maxRimSwing: Double = .pi / 6.4   // ±28°

/// Блик на кромке. Отдельная листовая вьюха намеренно: она одна подписана на
/// `DeviceTilt`, поэтому 30 обновлений в секунду перерисовывают только обводку,
/// а не экран целиком.
private struct MotionRimOverlay<S: Shape>: View {
    let shape: S
    let lineWidth: CGFloat
    let intensity: Double

    // Объект живёт вне вьюхи, поэтому Observed, а не State
    @ObservedObject private var tilt = DeviceTilt.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // GeometryReader нужен ради размера: по нему считается направление на
        // угол фигуры. В overlay он раскладку не трогает.
        GeometryReader { geo in
            shape
                .stroke(gradient(in: geo.size), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
        .onAppear { if !reduceMotion { tilt.subscribe() } }
        .onDisappear { if !reduceMotion { tilt.unsubscribe() } }
    }

    /// Качание вокруг угла вместо кругов по периметру. `sin` даёт гладкое
    /// ограниченное колебание: за `maxSwing` пятно не уходит и оборот не
    /// наматывает. При Reduce Motion — ноль, то есть ровно угол.
    private var swing: Double {
        reduceMotion ? 0 : sin(tilt.angle - DeviceTilt.neutralAngle) * maxRimSwing
    }

    /// Узкая яркая точка вместо размазанной по четверти окружности: именно
    /// из-за ширины предыдущий блик почти не читался на экране.
    ///
    /// Пятна привязаны к диагонали «левый верхний — правый нижний». Основное
    /// стоит на `location 0.25`, то есть в четверти оборота от `angle`, —
    /// отсюда сдвиг на `-.pi/2`. Второе на `0.75` попадает ровно напротив,
    /// в правый нижний угол, само собой.
    private func gradient(in size: CGSize) -> AngularGradient {
        let corner = atan2(-size.height / 2, -size.width / 2)
        let angle = corner + swing - .pi / 2
        return AngularGradient(
            stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(intensity * 0.12), location: 0.17),
                .init(color: .white.opacity(intensity), location: 0.25),
                .init(color: .white.opacity(intensity * 0.12), location: 0.33),
                .init(color: .white.opacity(0), location: 0.48),
                // вторичный отблеск с противоположной стороны, вдвое слабее
                .init(color: .white.opacity(intensity * 0.1), location: 0.68),
                .init(color: .white.opacity(intensity * 0.5), location: 0.75),
                .init(color: .white.opacity(intensity * 0.1), location: 0.82),
                .init(color: .white.opacity(0), location: 1)
            ],
            center: .center,
            angle: .radians(angle)
        )
    }
}

extension View {
    /// Кромка со бликом, который следует за наклоном устройства.
    func motionRim<S: Shape>(in shape: S, lineWidth: CGFloat = 1, intensity: Double = 0.7) -> some View {
        overlay {
            MotionRimOverlay(shape: shape, lineWidth: lineWidth, intensity: intensity)
        }
    }
}
