import SwiftUI

/// Облачко прослушивания: стеклянная пилюля со скрученной лентой света.
///
/// Рисует целиком шейдер `cloudOrb` (`CloudGlass.metal`): форма, стекло и
/// лента считаются на каждый пиксель. Отсюда в него уходят размер, время и
/// громкость. Форма и дыхание в тишине — `CloudMath` (Core/Pure).
struct SoundCapsule: View {
    /// Громкость 0…1. В тишине облачко всё равно дышит — `CloudMath.drive`.
    var level: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            let seconds = reduceMotion ? 2 : timeline.date.timeIntervalSinceReferenceDate
            let drive = CloudMath.drive(level: level, at: seconds)
            // Шейдеру время идёт числом одинарной точности: секунды от
            // 2001 года в нём теряют доли, поэтому отдаём остаток от часа.
            let time = seconds.truncatingRemainder(dividingBy: 3600)

            Rectangle()
                .fill(.black)
                // Размер берёт `visualEffect`, а не `@State`: геометрия
                // читается на этапе отрисовки и раскладку не трогает (TRAPS.md).
                .visualEffect { content, proxy in
                    let a = proxy.size.width * CloudMath.pillWidth / 2
                    let b = a / CloudMath.pillAspect
                    return content.colorEffect(
                        ShaderLibrary.cloudOrb(.float2(proxy.size), .float2(a, b),
                                               .float(CloudMath.squircle),
                                               .float(time), .float(drive)))
                }
        }
        .aspectRatio(CloudMath.aspect, contentMode: .fit)
        .accessibilityLabel("Индикатор прослушивания")
    }
}

#Preview("Облачко") {
    VStack(spacing: 32) {
        SoundCapsule(level: 0)
        SoundCapsule(level: 0.8)
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black)
}
