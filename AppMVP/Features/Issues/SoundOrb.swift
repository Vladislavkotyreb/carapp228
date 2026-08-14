import SwiftUI

/// Живой шар с экрана «Ошибки» (нода `46100:2764`). В макете это растровая
/// заглушка, поэтому рисуем сами.
///
/// Через `Canvas` и `TimelineView`, а не `MeshGradient`: последний требует
/// iOS 18, а таргет проекта 17.0. Заодно волной можно управлять точно —
/// mesh пришлось бы подгонять контрольными точками.
struct SoundOrb: View {
    /// Громкость 0…1. В тишине шар всё равно дышит: мёртвая картинка на
    /// экране про прослушивание двигателя выглядит как сломанная.
    var level: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Пропорция из макета: 370 × 238.955.
    static let aspectRatio: CGFloat = 370 / 238.955

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, time: phase(at: timeline.date))
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .background(Figma.graysBlack)
        .clipShape(OrbShape())
        .accessibilityLabel("Индикатор прослушивания")
    }

    /// При Reduce Motion время замирает — остаётся тот же градиент, но
    /// неподвижный. Требование HIG, так же сделано у блика на кромке.
    private func phase(at date: Date) -> Double {
        reduceMotion ? 0 : date.timeIntervalSinceReferenceDate
    }

    // MARK: - Отрисовка

    /// Ленты рисуются от дальней к ближней: у дальних больше размытие и
    /// меньше непрозрачность, отсюда ощущение глубины.
    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let ribbons: [(color: Color, speed: Double, frequency: Double,
                       amplitude: Double, thickness: Double, blur: Double, opacity: Double)] = [
            (Figma.orbViolet, 0.35, 1.1, 0.30, 0.42, 26, 0.55),
            (Figma.orbTeal,   0.55, 1.6, 0.24, 0.30, 16, 0.70),
            (Figma.orbGreen,  0.80, 2.1, 0.18, 0.18,  9, 0.95)
        ]

        for ribbon in ribbons {
            var inner = context
            inner.addFilter(.blur(radius: ribbon.blur))
            inner.opacity = ribbon.opacity

            let path = wave(in: size, time: time * ribbon.speed,
                            frequency: ribbon.frequency, amplitude: ribbon.amplitude)

            inner.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [ribbon.color.opacity(0), ribbon.color, ribbon.color.opacity(0)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                style: StrokeStyle(lineWidth: size.height * ribbon.thickness, lineCap: .round)
            )
        }
    }

    /// Синусоида с затуханием к краям: без него лента упирается в границу
    /// шара обрубленным концом.
    private func wave(in size: CGSize, time: Double,
                      frequency: Double, amplitude: Double) -> Path {
        // Дыхание держит шар живым в тишине, громкость добавляется поверх.
        let breathing = 0.35 + 0.15 * sin(time * 0.9)
        let swing = size.height * amplitude * (breathing + level)

        var path = Path()
        let steps = 48
        for step in 0...steps {
            let ratio = Double(step) / Double(steps)
            let x = size.width * ratio
            // Затухание к краям — половина периода синуса по всей ширине
            let envelope = sin(ratio * .pi)
            let y = size.height / 2
                + sin(ratio * .pi * 2 * frequency + time * 2) * swing * envelope

            let point = CGPoint(x: x, y: y)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Форма шара: почти эллипс, но со слегка приплюснутыми боками — как в
/// макете. Скругление берём от меньшей стороны, чтобы пропорция не ломала его.
private struct OrbShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: rect.height * 0.5, style: .continuous).path(in: rect)
    }
}
