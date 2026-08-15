import SwiftUI

/// Живой шар с экрана «Ошибки» (нода `46100:2764`). В макете это растровая
/// заглушка, поэтому рисуем сами.
///
/// Через `Canvas` и `TimelineView`, а не `MeshGradient`: последний требует
/// iOS 18, а таргет проекта 17.0. Заодно волной можно управлять точно —
/// mesh пришлось бы подгонять контрольными точками.
/// Какой шар рисуем. Переключается одной константой ниже — откат к прежнему
/// виду это замена `.blob` на `.wave`, ничего больше трогать не надо.
enum OrbStyle {
    /// Растр из макета плюс живая волна поверх. В покое совпадает с Figma
    /// точь в точь, потому что это буквально тот же файл.
    case figma
    /// Волна внутри пузыря — то, что было сделано по макету.
    case wave
    /// Морфящийся контур: 24 радиальные точки, радиус гнут три синусоиды,
    /// точки соединены квадратичными кривыми. Подход взят из
    /// voice-orb-visualizer (MIT, OrbitingBucket) — это веб-библиотека на
    /// Canvas 2D, поэтому не подключена, а переписана под наш Canvas.
    case blob
    /// Облако точек на сфере — вариант «particles» из демо voice-orb.
    /// Кода частиц в репозитории библиотеки нет (в `src/core` только
    /// `VoiceOrb`, `audio-pipeline`, `forces`, `utils`), поэтому перенесён
    /// приём, а не реализация.
    case particles
}

struct SoundOrb: View {
    /// Единственное место переключения.
    static let style: OrbStyle = .figma

    /// Громкость 0…1. В тишине шар всё равно дышит: мёртвая картинка на
    /// экране про прослушивание двигателя выглядит как сломанная.
    var level: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Пропорция из макета: 370 × 238.955.
    static let aspectRatio: CGFloat = 370 / 238.955

    var body: some View {
        if Self.style == .figma {
            figmaOrb
        } else {
            generated
        }
    }

    /// Ассет из макета как основа, живая волна — сверху. При нулевой громкости
    /// волны нет вовсе, и на экране ровно то, что нарисовано в Figma.
    private var figmaOrb: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let t = phase(at: timeline.date)

            GeometryReader { geo in
                ZStack {
                    // Геометрия из ноды: картинка выше кадра на 24.3 % и
                    // сдвинута вверх на 15.9 %, лишнее обрезается рамкой.
                    Image("SoundOrbBase")
                        .resizable()
                        .frame(width: geo.size.width, height: geo.size.height * 1.243)
                        .offset(y: -geo.size.height * 0.159)
                        // Статичная лента с картинки гаснет по мере того, как
                        // разгорается живая: иначе две ленты спорят.
                        .opacity(1 - 0.55 * min(1, level * 2.2))

                    Canvas { context, size in
                        drawLiveWave(in: &context, size: size, time: t)
                    }
                }
            }
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .clipShape(OrbShape())
            // Оболочка горит зелёным тем ярче, чем громче звук
            .overlay(
                OrbShape()
                    .stroke(Figma.orbBody, lineWidth: 1)
                    .blur(radius: 6)
                    .opacity(0.15 + 0.85 * level)
            )
            .overlay(OrbShape().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        }
    }

    private var generated: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { context, size in
                let t = phase(at: timeline.date)
                switch Self.style {
                case .figma, .wave: draw(in: &context, size: size, time: t)
                case .blob: drawBlob(in: &context, size: size, time: t)
                case .particles: drawParticles(in: &context, size: size, time: t)
                }
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        // Подложка не плоско-чёрная: в макете у шара виден объём, к краям
        // он темнее фона экрана, отсюда радиальная заливка.
        .background(
            RadialGradient(colors: [Color(white: 0.10), Figma.graysBlack],
                           center: .center, startRadius: 0, endRadius: 210)
        )
        .clipShape(OrbShape())
        // Тонкая кромка — та же волосяная линия, что у тёмных карточек
        .overlay(OrbShape().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
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
    ///
    /// Пропорции подобраны по макету: рассеянного свечения там мало, а сама
    /// волна собранная и яркая. Первая версия была наоборот — облако без
    /// формы, — поэтому ядро сделано тонким и почти без размытия.
    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let ribbons: [(color: Color, speed: Double, frequency: Double,
                       amplitude: Double, thickness: Double, blur: Double, opacity: Double)] = [
            // дальнее свечение — задаёт цветовое пятно, формы не несёт
            (Figma.orbViolet, 0.30, 0.9, 0.26, 0.30, 30, 0.40),
            (Figma.orbTeal,   0.45, 1.3, 0.20, 0.16, 14, 0.55),
            // ядро: тонкое и резкое, именно оно читается как волна
            (Figma.orbGreen,  0.70, 1.7, 0.15, 0.045, 2.5, 1.0),
            (Color.white,     0.70, 1.7, 0.15, 0.014, 1.0, 0.85)
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
            // Степень выше единицы поджимает волну к центру: у пузыря концы
            // скруглены, и на громком звуке гребни вылезали за его край.
            let envelope = pow(sin(ratio * .pi), 1.4)
            let y = size.height / 2
                + sin(ratio * .pi * 2 * frequency + time * 2) * swing * envelope

            let point = CGPoint(x: x, y: y)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

extension SoundOrb {
    /// Морфящийся контур. Радиус в каждой из 24 точек гнут три синусоиды с
    /// разной частотой и направлением — так контур не пульсирует «дыркой», а
    /// перекатывается. Пропорции коэффициентов взяты из voice-orb-visualizer.
    fileprivate func drawBlob(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // Контур круглый, а место у нас вытянутое — растягиваем по x, иначе
        // шар займёт лишь среднюю треть.
        let stretch = size.width / size.height
        let base = size.height / 2 * 0.78

        // В тишине контур почти ровный, звук раскачивает его.
        let amplitude = size.height * (0.02 + 0.16 * level)

        let path = blobPath(center: center, base: base, stretch: stretch,
                            amplitude: amplitude, time: time)

        // Мягкое свечение позади и плотное ядро поверх — на плоской заливке,
        // как в оригинале, шар выглядит наклейкой.
        var glow = context
        glow.addFilter(.blur(radius: 34))
        glow.opacity = 0.55
        glow.fill(path, with: .linearGradient(orbGradient, startPoint: .zero,
                                              endPoint: CGPoint(x: size.width, y: size.height)))

        context.fill(path, with: .linearGradient(orbGradient, startPoint: .zero,
                                                 endPoint: CGPoint(x: size.width, y: size.height)))

        var sheen = context
        sheen.addFilter(.blur(radius: 12))
        sheen.opacity = 0.5
        sheen.stroke(path, with: .color(.white), lineWidth: 2)
    }

    private var orbGradient: Gradient {
        Gradient(colors: [Figma.orbViolet, Figma.orbTeal, Figma.orbGreen])
    }

    /// Точки соединяются квадратичными кривыми через середины отрезков —
    /// иначе на 24 точках виден многоугольник.
    private func blobPath(center: CGPoint, base: Double, stretch: Double,
                          amplitude: Double, time: Double) -> Path {
        let count = 24
        var points: [CGPoint] = []
        points.reserveCapacity(count)

        for index in 0..<count {
            let angle = Double(index) / Double(count) * 2 * .pi
            let wave = sin(angle * 2 + time * 2) * amplitude
                + sin(angle * 3 - time * 1.5) * amplitude * 0.6
                + sin(angle * 1.5 + time * 2.5) * amplitude * 0.4
            let radius = base + wave
            points.append(CGPoint(x: center.x + cos(angle) * radius * stretch,
                                  y: center.y + sin(angle) * radius))
        }

        var path = Path()
        let midpoint: (CGPoint, CGPoint) -> CGPoint = { a, b in
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        path.move(to: midpoint(points[count - 1], points[0]))
        for index in 0..<count {
            let current = points[index]
            let next = points[(index + 1) % count]
            path.addQuadCurve(to: midpoint(current, next), control: current)
        }
        path.closeSubpath()
        return path
    }
}

/// Одна точка облака. Набор считается один раз и живёт статически: если
/// пересоздавать его каждый кадр, облако мерцает телевизионным шумом вместо
/// того чтобы вращаться.
private struct Particle {
    let x, y, z: Double
    /// Своя фаза турбулентности — иначе всё облако дышит синхронно.
    let phase: Double
    let jitter: Double
}

private enum ParticleCloud {
    /// Девять тысяч точек: на скриншоте у автора демо облако плотное, из
    /// десятков тысяч крошечных точек. Меньше — видно отдельные точки,
    /// заметно больше — кадр перестаёт держать 30 fps.
    static let points: [Particle] = build(count: 9000)

    private static func build(count: Int) -> [Particle] {
        // Фиксированное зерно: облако должно быть одинаковым между запусками,
        // иначе не сверить кадры.
        var seed: UInt64 = 0x5EED_1234
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 11) & 0xFFFF_FFFF) / Double(0xFFFF_FFFF)
        }

        return (0..<count).map { index in
            // Направление равномерно по сфере
            let u = random() * 2 - 1
            let theta = random() * 2 * .pi
            let ring = sqrt(max(0, 1 - u * u))

            // Радиус со смещением к поверхности, а каждая десятая точка
            // улетает наружу — это и даёт рассеянный ореол вокруг шара.
            let halo = index % 10 == 0
            let base = pow(random(), 1.0 / 2.2)
            let radius = halo ? 1.0 + random() * 0.45 : base

            return Particle(x: cos(theta) * ring * radius,
                            y: u * radius,
                            z: sin(theta) * ring * radius,
                            phase: random() * 2 * .pi,
                            jitter: 0.01 + random() * 0.03)
        }
    }
}

extension SoundOrb {
    /// Плотное облако точек. Рисуется **двумя** заливками, а не шестью
    /// тысячами: каждый вызов `fill` дорог, поэтому все точки собираются в
    /// один `Path` мелкими прямоугольниками. Ближняя треть идёт вторым
    /// проходом ярче — от этого появляется объём.
    fileprivate func drawParticles(in context: inout GraphicsContext,
                                   size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let stretch = size.width / size.height
        let radius = size.height / 2 * (0.62 + 0.14 * level)
        let spin = time * 0.28
        let sway = 0.35 + level

        var far = Path()
        var near = Path()

        for particle in ParticleCloud.points {
            // Поворот вокруг вертикальной оси
            let angle = atan2(particle.z, particle.x) + spin
            let plane = sqrt(particle.x * particle.x + particle.z * particle.z)
            let wobble = sin(time * 1.6 + particle.phase) * particle.jitter * sway

            let x = cos(angle) * (plane + wobble)
            let z = sin(angle) * (plane + wobble)
            let y = particle.y + wobble

            let point = CGPoint(x: center.x + x * radius * stretch,
                                y: center.y + y * radius)

            // Дальние точки мельче: без этого шар читается плоским диском
            let depth = (z / max(plane, 0.001) + 1) / 2
            let dot = depth > 0.66 ? 1.3 : 1.0
            let rect = CGRect(x: point.x, y: point.y, width: dot, height: dot)

            if depth > 0.66 { near.addRect(rect) } else { far.addRect(rect) }
        }

        context.fill(far, with: .color(Figma.orbParticle.opacity(0.32 + 0.2 * level)))
        context.fill(near, with: .color(Figma.orbParticle.opacity(0.7 + 0.3 * level)))

        var glow = context
        glow.addFilter(.blur(radius: 18))
        glow.opacity = 0.35 + 0.25 * level
        glow.fill(near, with: .color(Figma.orbParticle))
    }
}

extension SoundOrb {
    /// Живая лента поверх растра. Появляется только со звуком: при нулевой
    /// громкости прозрачна целиком, и макет остаётся нетронутым.
    ///
    /// Перелив сделан отдельным бликом со своей фазой — одной синусоиды для
    /// него мало, она даёт только колебание, но не перетекание света.
    fileprivate func drawLiveWave(in context: inout GraphicsContext,
                                  size: CGSize, time: Double) {
        guard level > 0.01 else { return }
        let strength = min(1, level * 2.2)

        let ribbons: [(color: Color, speed: Double, frequency: Double,
                       thickness: Double, blur: Double, opacity: Double)] = [
            (Figma.orbDeep, 0.30, 0.9, 0.26, 26, 0.55),
            (Figma.orbBody, 0.48, 1.3, 0.13, 12, 0.75),
            (Figma.orbCore, 0.70, 1.7, 0.035, 2, 1.0)
        ]

        for ribbon in ribbons {
            var layer = context
            layer.addFilter(.blur(radius: ribbon.blur))
            layer.opacity = ribbon.opacity * strength

            let path = wave(in: size, time: time * ribbon.speed,
                            frequency: ribbon.frequency, amplitude: 0.17)
            layer.stroke(path, with: .color(ribbon.color),
                         style: StrokeStyle(lineWidth: size.height * ribbon.thickness,
                                            lineCap: .round))
        }

        // Перелив: узкий яркий блик бежит вдоль ленты своим темпом
        var sheen = context
        sheen.addFilter(.blur(radius: 6))
        sheen.opacity = strength * 0.9
        let shine = wave(in: size, time: time * 1.15, frequency: 1.7, amplitude: 0.17)
        sheen.stroke(shine, with: .linearGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: Figma.orbCore, location: shinePosition(at: time)),
                .init(color: .clear, location: 1)
            ]),
            startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                     style: StrokeStyle(lineWidth: size.height * 0.06, lineCap: .round))
    }

    /// Положение блика 0…1, ходит туда-сюда, а не прыгает с края на край.
    private func shinePosition(at time: Double) -> Double {
        0.5 + 0.45 * sin(time * 0.8)
    }
}

/// Форма шара: почти эллипс, но со слегка приплюснутыми боками — как в
/// макете. Скругление берём от меньшей стороны, чтобы пропорция не ломала его.
private struct OrbShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: rect.height * 0.5, style: .continuous).path(in: rect)
    }
}
