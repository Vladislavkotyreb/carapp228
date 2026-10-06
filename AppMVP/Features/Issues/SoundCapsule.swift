import SwiftUI

/// Облачко прослушивания: стеклянная капсула, внутри волна или «фары».
///
/// Расчёты — в `CloudMath` (Core/Pure), здесь только рисование. Рисунок свой,
/// не перенос облачка No Tipe: их лицензия запрещает и копию, и перевод.
/// Тот же рисунок в браузере — демо по ссылке в шапке `CloudMath.swift`.
///
/// Слои снизу вверх: тело капсулы → отсвет на дне → волна или фары →
/// внутренняя тень по краю (толщина стекла) → блик сверху → ободок, который
/// к низу берёт цвет волны и разгорается со звуком.
struct SoundCapsule: View {
    enum Content {
        case wave
        case eyes
    }

    /// Громкость 0…1. В тишине облачко всё равно дышит — `CloudMath.drive`.
    var level: Double
    var palette: CloudPalette = .aurora
    var content: Content = .wave
    var mood: CloudMood = .listen

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Смена настроения идёт 0.35 с от прежнего лица к новому. Состояние
    /// пишется только в момент смены, а не на каждом кадре, — кадровое
    /// `@State` ломает соседний скролл (TRAPS.md).
    @State private var previousMood: CloudMood = .listen
    @State private var moodChangedAt: Date = .distantPast

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let now = timeline.date
                let time = reduceMotion ? 2 : now.timeIntervalSinceReferenceDate
                let progress = CloudMath.moodProgress(elapsed: now.timeIntervalSince(moodChangedAt))
                let face = CloudFace.of(previousMood).mixed(with: .of(mood), progress)
                draw(in: &context, size: size, time: time, face: face)
            }
        }
        .aspectRatio(CloudMath.aspect, contentMode: .fit)
        .onChange(of: mood) { oldValue, _ in
            previousMood = oldValue
            moodChangedAt = .now
        }
        .onAppear { previousMood = mood }
        .accessibilityLabel("Индикатор прослушивания")
    }

    // MARK: - Капсула

    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double, face: CloudFace) {
        let level = CloudMath.drive(level: level, at: time)
        // Отступ под ободок и его свечение: иначе их срежет край кадра.
        let inset = size.height * 0.03
        let a = size.width / 2 - inset
        let b = a / CloudMath.aspect
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let shape = capsule(center: center, a: a, b: b)
        let box = CGRect(x: center.x - a, y: center.y - b, width: a * 2, height: b * 2)
        let tint = content == .eyes
            ? palette.glow.mixed(with: CloudPalette.amber, face.amber)
            : palette.glow

        // Тело: темнее к краям — у стекла есть объём.
        context.fill(shape, with: .radialGradient(
            Gradient(colors: [Color(red: 14 / 255, green: 18 / 255, blue: 24 / 255),
                              Color(red: 4 / 255, green: 5 / 255, blue: 7 / 255)]),
            center: CGPoint(x: center.x, y: center.y + b * 0.15),
            startRadius: b * 0.2, endRadius: a * 1.05))

        var inner = context
        inner.clip(to: shape)

        // Отсвет на дне: свет волны отражается от низа капсулы.
        inner.fill(Path(box), with: .radialGradient(
            Gradient(colors: [color(tint, 0.18 + 0.25 * level), color(tint, 0)]),
            center: CGPoint(x: center.x, y: center.y + b * 1.1),
            startRadius: 0, endRadius: a))

        switch content {
        case .wave: drawWave(in: inner, box: box, level: level, time: time)
        case .eyes: drawEyes(in: inner, box: box, level: level, time: time, face: face)
        }

        // Внутренняя тень по краю — толщина стекла.
        var rimShadow = inner
        rimShadow.addFilter(.blur(radius: b * 0.08))
        rimShadow.stroke(shape, with: .color(.black.opacity(0.55)), lineWidth: b * 0.22)

        // Блик: мягкое пятно в верхней части и узкая полоса у кромки.
        let highlight = capsule(center: CGPoint(x: center.x, y: center.y - b * 0.42),
                                a: a * 0.84, b: b * 0.52, n: 3)
        inner.fill(highlight, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.075), .white.opacity(0)]),
            startPoint: CGPoint(x: center.x, y: center.y - b),
            endPoint: CGPoint(x: center.x, y: center.y - b * 0.05)))
        let streak = Path { path in
            path.addArc(center: .zero, radius: 1, startAngle: .radians(.pi * 1.1),
                        endAngle: .radians(.pi * 1.55), clockwise: false)
        }
        .applying(CGAffineTransform(translationX: center.x - a * 0.22, y: center.y - b * 0.8)
            .scaledBy(x: a * 0.4, y: b * 0.12))
        inner.stroke(streak, with: .color(.white.opacity(0.35)),
                     style: StrokeStyle(lineWidth: max(1, b * 0.018), lineCap: .round))

        // Ободок: светлый сверху слева, к низу — цвет волны, ярче со звуком.
        var rim = context
        rim.addFilter(.shadow(color: color(tint, 0.6 * level), radius: b * 0.12 * level))
        rim.stroke(shape, with: .linearGradient(
            Gradient(stops: [
                .init(color: .white.opacity(0.55), location: 0),
                .init(color: .white.opacity(0.08), location: 0.45),
                .init(color: color(tint, 0.25 + 0.55 * level), location: 1),
            ]),
            startPoint: CGPoint(x: center.x - a, y: center.y - b),
            endPoint: CGPoint(x: center.x + a * 0.4, y: center.y + b)),
            lineWidth: max(1, b * 0.02))
    }

    // MARK: - Волна

    /// Четыре ленты от дальней к ближней: широкие и размытые дают цветовое
    /// пятно, узкие и резкие — саму волну. Сложение `plusLighter`, как свет.
    private func drawWave(in context: GraphicsContext, box: CGRect, level: Double, time: Double) {
        let ribbons: [(color: CloudRGB, k: Double, speed: Double, phase: Double,
                       width: Double, blur: Double, opacity: Double)] = [
            (palette.deep, 0.9, 0.9, 0.0, 0.11, 34, 0.55),
            (palette.mid, 1.15, 1.3, 1.7, 0.05, 20, 0.7),
            (palette.glow, 1.4, 1.8, 3.1, 0.022, 10, 0.95),
            (palette.core, 1.4, 1.8, 3.1, 0.007, 4, 0.9),
        ]
        let midline = box.minY + box.height * 0.53
        let amplitude = box.height * (0.07 + 0.2 * level)

        for ribbon in ribbons {
            var layer = context
            layer.blendMode = .plusLighter
            layer.addFilter(.shadow(color: color(ribbon.color, 0.9),
                                    radius: ribbon.blur * (0.6 + 0.8 * level) / 2))
            let path = Path { path in
                for i in 0...80 {
                    let u = Double(i) / 80
                    let point = CGPoint(
                        x: box.minX + box.width * u,
                        y: midline + amplitude * CloudMath.wave(u, time: time, k: ribbon.k,
                                                                 speed: ribbon.speed, phase: ribbon.phase))
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            let strength = ribbon.opacity * (0.55 + 0.45 * level)
            layer.stroke(path, with: .linearGradient(
                Gradient(colors: [color(ribbon.color, 0), color(ribbon.color, strength), color(ribbon.color, 0)]),
                startPoint: CGPoint(x: box.minX, y: 0), endPoint: CGPoint(x: box.maxX, y: 0)),
                style: StrokeStyle(lineWidth: max(1, box.height * ribbon.width * (0.7 + 0.6 * level)),
                                   lineCap: .round))
        }
    }

    // MARK: - Фары

    /// Персонаж — две фары. Горячая точка проектора и есть взгляд, полоса
    /// ходовых огней по верхней кромке — бровь.
    private func drawEyes(in context: GraphicsContext, box: CGRect, level: Double,
                          time: Double, face: CloudFace) {
        let size = min(box.width * 0.16, box.height * 0.36)
        let midline = box.midY + box.height * 0.02
        let led = palette.led.mixed(with: CloudPalette.amber, face.amber)
        let glow = palette.glow.mixed(with: CloudPalette.amber, face.amber)
        let shake = face.amber * level * sin(time * 46) * size * 0.05
        let gaze = face.look * CloudMath.gaze(at: time, level: level)
        let brightness = face.dim * (0.55 + 0.45 * level)
        let blink = CloudMath.blink(at: time)

        for side in [-1.0, 1.0] {
            let cx = box.midX + side * box.width * 0.2 + shake

            if face.happy > 0.5 {
                // «Всё хорошо»: фары щурятся дугой вверх.
                var arc = context
                arc.addFilter(.shadow(color: color(glow, 0.9), radius: size * 0.3))
                let path = Path { path in
                    path.addArc(center: CGPoint(x: cx, y: midline + size * 0.28), radius: size * 0.62,
                                startAngle: .radians(.pi * 1.15), endAngle: .radians(.pi * 1.85),
                                clockwise: false)
                }
                arc.stroke(path, with: .color(color(led, 0.95 * brightness)),
                           style: StrokeStyle(lineWidth: size * 0.16, lineCap: .round))
                continue
            }

            let open = max(0.06, face.open * blink)
            let lensPath = lens(cx: cx, cy: midline, side: side, size: size, open: open, tilt: face.tilt)

            context.fill(lensPath, with: .linearGradient(
                Gradient(colors: [Color(red: 21 / 255, green: 26 / 255, blue: 34 / 255),
                                  Color(red: 7 / 255, green: 9 / 255, blue: 12 / 255)]),
                startPoint: CGPoint(x: cx, y: midline - size * 0.6),
                endPoint: CGPoint(x: cx, y: midline + size * 0.6)))
            var edge = context
            edge.addFilter(.shadow(color: color(glow, 0.8 * brightness), radius: size * 0.25))
            edge.stroke(lensPath, with: .color(color(led, 0.55 * brightness)), lineWidth: max(1, size * 0.05))

            var inside = context
            inside.clip(to: lensPath)
            inside.blendMode = .plusLighter
            let pupil = CGPoint(x: cx + gaze * size * 0.38 - side * size * 0.05,
                                y: midline + size * 0.06 * open)
            inside.fill(Path(ellipseIn: CGRect(x: pupil.x - size * 0.42, y: pupil.y - size * 0.42,
                                               width: size * 0.84, height: size * 0.84)),
                        with: .radialGradient(
                            Gradient(stops: [
                                .init(color: .white.opacity(0.95 * brightness), location: 0),
                                .init(color: color(led, 0.85 * brightness), location: 0.25),
                                .init(color: color(glow, 0), location: 1),
                            ]),
                            center: pupil, startRadius: 0, endRadius: size * 0.42))

            let hw = size * 0.78
            let drl = Path { path in
                path.move(to: CGPoint(x: cx - side * hw, y: midline - size * 0.32 * open + face.tilt * size * 0.42))
                path.addQuadCurve(to: CGPoint(x: cx + side * hw - side * size * 0.1, y: midline - size * 0.42 * open),
                                  control: CGPoint(x: cx, y: midline - size * 0.52 * open))
            }
            inside.stroke(drl, with: .color(color(led, 0.9 * brightness)), lineWidth: max(1.2, size * 0.07))
        }
    }

    /// Фара скошена наружу: внешний край выше и шире внутреннего — так
    /// читается морда машины. `tilt` опускает внутренний верхний угол.
    private func lens(cx: Double, cy: Double, side: Double, size s: Double,
                      open: Double, tilt: Double) -> Path {
        let hw = s * 0.78, outer = s * 0.5 * open, innerHalf = s * 0.36 * open
        let xi = cx - side * hw, xo = cx + side * hw
        let drop = tilt * s * 0.45
        return Path { path in
            path.move(to: CGPoint(x: xi, y: cy - innerHalf + drop))
            path.addCurve(to: CGPoint(x: xo, y: cy - outer * 0.55),
                          control1: CGPoint(x: cx - side * hw * 0.2, y: cy - outer * 1.05 + drop * 0.4),
                          control2: CGPoint(x: xo - side * s * 0.25, y: cy - outer))
            path.addQuadCurve(to: CGPoint(x: xo - side * s * 0.12, y: cy + outer * 0.62),
                              control: CGPoint(x: xo + side * s * 0.06, y: cy + outer * 0.2))
            path.addCurve(to: CGPoint(x: xi, y: cy + innerHalf * 0.55),
                          control1: CGPoint(x: cx + side * hw * 0.2, y: cy + outer * 0.9),
                          control2: CGPoint(x: cx - side * hw * 0.5, y: cy + innerHalf))
            path.addQuadCurve(to: CGPoint(x: xi, y: cy - innerHalf + drop),
                              control: CGPoint(x: xi - side * s * 0.05, y: cy))
            path.closeSubpath()
        }
    }

    // MARK: - Помощники

    private func capsule(center: CGPoint, a: Double, b: Double,
                         n: Double = CloudMath.squircle) -> Path {
        Path { path in
            for i in 0...96 {
                let p = CloudMath.capsulePoint(Double(i) / 96 * 2 * .pi, a: a, b: b, n: n)
                let point = CGPoint(x: center.x + p.x, y: center.y + p.y)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }

    private func color(_ rgb: CloudRGB, _ opacity: Double) -> Color {
        Color(red: rgb.r, green: rgb.g, blue: rgb.b).opacity(opacity)
    }
}

#Preview("Облачко") {
    VStack(spacing: 24) {
        SoundCapsule(level: 0.5, palette: .aurora)
        SoundCapsule(level: 0.5, palette: .prism)
        HStack(spacing: 16) {
            SoundCapsule(level: 0.4, palette: .aurora, content: .eyes, mood: .listen)
            SoundCapsule(level: 0.6, palette: .prism, content: .eyes, mood: .knock)
        }
    }
    .padding(24)
    .background(Color.black)
}
