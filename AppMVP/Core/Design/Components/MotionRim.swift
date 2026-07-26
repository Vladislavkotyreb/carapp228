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

    /// Направление «источника света» в системе координат экрана, радианы.
    @Published private(set) var angle: Double = -.pi / 2

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
        shape
            .stroke(gradient, lineWidth: lineWidth)
            .allowsHitTesting(false)
            .onAppear { if !reduceMotion { tilt.subscribe() } }
            .onDisappear { if !reduceMotion { tilt.unsubscribe() } }
    }

    /// При Reduce Motion угол фиксируем — блик остаётся, но не двигается.
    private var angle: Double { reduceMotion ? -.pi / 2 : tilt.angle }

    private var gradient: AngularGradient {
        AngularGradient(
            stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(intensity), location: 0.25),
                .init(color: .white.opacity(0), location: 0.5),
                .init(color: .white.opacity(intensity * 0.6), location: 0.75),
                .init(color: .white.opacity(0), location: 1)
            ],
            center: .center,
            angle: .radians(angle)
        )
    }
}

extension View {
    /// Кромка со бликом, который следует за наклоном устройства.
    func motionRim<S: Shape>(in shape: S, lineWidth: CGFloat = 0.5, intensity: Double = 0.5) -> some View {
        overlay {
            MotionRimOverlay(shape: shape, lineWidth: lineWidth, intensity: intensity)
        }
    }
}
