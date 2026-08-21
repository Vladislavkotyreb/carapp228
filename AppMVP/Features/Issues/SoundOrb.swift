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

    /// Активность шара в тишине. Ноль означал бы мёртвую картинку — на
    /// референсной записи шар не замирает нигде.
    ///
    /// Важно, что это **вилка**, а не одно число. С постоянным уровнем в покое
    /// движется только геометрия ленты, и по замеру это давало 5.6/255 против
    /// 19 у референса. На записи каждый кадр гонит сам голос: вместе с
    /// толщиной скачет и яркость. Поэтому уровень в тишине сам дышит между
    /// этими границами — тем же приёмом, только предсказуемо.
    static let idleLow: Double = 0.58
    static let idleHigh: Double = 1.0

    /// Уровень, которым живёт лента: в тишине дышит сам, с голосом идёт за ним.
    /// Две синусоиды с несоизмеримыми частотами — чтобы рисунок не повторялся
    /// заметным периодом.
    ///
    /// Частоты подняты втрое против первой версии, и это не «покрутил ручку».
    /// Замер по кадрам через 1/30 с: у референса толщина проходит полный цикл
    /// подъёма и спада за 0.65 с, а у прежней версии за то же время только
    /// сползала — 38 % в 21 %. Монотонное сползание и читается вялым.
    ///
    /// `shaped` делает подъём круче спада. На записи за лентой стоит голос, а
    /// у него атака резкая: симметричная синусоида этого не даёт, сколько её
    /// ни ускоряй.
    func drive(at time: Double) -> Double {
        let raw = (0.55 * sin(time * 3.4) + 0.45 * sin(time * 5.9 + 1.7) + 1) / 2
        let shaped = pow(raw, 0.62)
        let idle = Self.idleLow + (Self.idleHigh - Self.idleLow) * shaped
        return max(idle, min(1, level * 1.6))
    }

    var body: some View {
        if Self.style == .figma {
            figmaOrb
        } else {
            generated
        }
    }

    /// Ассет из макета как основа, живая волна — сверху. Пузырь, его объём и
    /// затухание к краям берутся с растра, движется только лента.
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
                        // разгорается живая: иначе две ленты спорят. Гасить
                        // приходится и в тишине — живая лента теперь работает
                        // всегда, а не только со звуком.
                        .opacity(1 - 0.55 * drive(at: t))

                    Canvas { context, size in
                        drawLiveWave(in: &context, size: size, time: t)
                    }
                }
            }
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .clipShape(OrbShape())
            // Оболочка горит зелёным тем ярче, чем громче звук — по кромке
            // самого пузыря, а не кадра.
            .overlay(
                BubbleShape()
                    .stroke(Figma.orbBody, lineWidth: 1.5)
                    .blur(radius: 5)
                    .opacity(0.10 + 0.40 * level)
            )
            .overlay(BubbleShape().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
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
    /// Живая лента поверх растра.
    ///
    /// Раньше здесь стоял ранний выход при тишине, и шар в покое стоял
    /// намертво. На референсной записи он не замирает никогда: средняя разница
    /// между кадрами через 1/6 секунды по зоне шара 19/255, и даже в самом
    /// спокойном месте 11.5. Поэтому лента рисуется всегда, а громкость только
    /// добавляется поверх базовой активности.
    ///
    /// Разбор референсной записи (24 кадра за 14 с) показал, что двигается там
    /// не средняя линия, а **толщина**: центр тяжести ленты гуляет всего на
    /// ±3 px из 106, тогда как её полувысота ходит от 7 до 75 px, и утолщение
    /// переезжает вдоль оси. Поэтому лента здесь — заливаемая фигура с
    /// переменной толщиной, а не обводка постоянной ширины: штрихом такое
    /// «набухание» не нарисовать в принципе.
    ///
    /// Второе наблюдение — цвет распределён по вертикали: сверху бирюзовая
    /// кромка (154,255,254), в середине мята (117,247,148), внизу зелень
    /// (79,174,105). Отсюда вертикальный градиент в каждом слое.
    fileprivate func drawLiveWave(in context: inout GraphicsContext,
                                  size: CGSize, time: Double) {
        let strength = drive(at: time)

        // Свет живёт внутри пузыря: на записи наружу не выходит ничего.
        let bubble = OrbBubble.rect(in: size)

        // Слои складываются светом: там, где ленты перекрываются, канал уходит
        // в потолок — ровно так на записи середина выбита в почти белый.
        var stack = context
        stack.blendMode = .plusLighter
        stack.clip(to: RoundedRectangle(cornerRadius: bubble.height / 2, style: .continuous)
            .path(in: bubble))
        stack.translateBy(x: bubble.minX, y: bubble.minY)

        let layers: [AuroraLayer] = [
            // Дальнее свечение: широкое, размытое, оно и красит весь пузырь
            AuroraLayer(thickness: 0.60, swing: 0.09, frequency: 0.8, speed: 1.6,
                        swell: 0.85, swellSpeed: 2.6, offset: -0.08, blur: 22,
                        opacity: 0.42, top: Figma.orbBody, middle: Figma.orbDeep,
                        bottom: Figma.orbGrass),
            // Тело ленты — то, что читается как волна
            AuroraLayer(thickness: 0.32, swing: 0.13, frequency: 1.2, speed: 2.4,
                        swell: 1.05, swellSpeed: 4.0, offset: -0.10, blur: 10,
                        opacity: 0.60, top: Figma.orbCore, middle: Figma.orbMint,
                        bottom: Figma.orbGrass),
            // Бирюзовая кромка поверху: на записи она отдельной тонкой полосой
            AuroraLayer(thickness: 0.07, swing: 0.13, frequency: 1.2, speed: 2.4,
                        swell: 0.95, swellSpeed: 4.0, offset: -0.175, blur: 4,
                        opacity: 0.75, top: Color.white, middle: Figma.orbCore,
                        bottom: Figma.orbCore)
        ]

        for layer in layers {
            var pass = stack
            pass.addFilter(.blur(radius: layer.blur))
            pass.opacity = layer.opacity * strength

            let path = ribbon(in: bubble.size, layer: layer, time: time)
            pass.fill(path, with: .linearGradient(
                Gradient(colors: [layer.top, layer.middle, layer.bottom]),
                startPoint: CGPoint(x: 0, y: bubble.height * 0.22),
                endPoint: CGPoint(x: 0, y: bubble.height * 0.78)))
        }

        // Перелив: яркое пятно бежит вдоль ленты своим темпом. Без него лента
        // колеблется, но не переливается — это разные ощущения.
        var sheen = stack
        sheen.addFilter(.blur(radius: 9))
        sheen.opacity = strength * 0.5
        let shine = ribbon(in: bubble.size, layer: layers[1], time: time)
        let centre = shinePosition(at: time)
        sheen.fill(shine, with: .linearGradient(
            Gradient(stops: [
                .init(color: .clear, location: max(0, centre - 0.3)),
                .init(color: Figma.orbCore, location: centre),
                .init(color: .clear, location: min(1, centre + 0.3))
            ]),
            startPoint: .zero, endPoint: CGPoint(x: bubble.width, y: 0)))
    }

    /// Настройки одной ленты. Собраны в тип, а не в кортеж: полей стало восемь,
    /// и на кортеже позиционные аргументы перестают читаться.
    fileprivate struct AuroraLayer {
        /// Доля высоты шара в самом толстом месте
        let thickness: Double
        /// Размах средней линии в долях высоты
        let swing: Double
        let frequency: Double
        let speed: Double
        /// Насколько сильно толщина гуляет вдоль оси, 0…1
        let swell: Double
        let swellSpeed: Double
        /// Сдвиг ленты по вертикали в долях высоты
        let offset: Double
        let blur: Double
        let opacity: Double
        let top, middle, bottom: Color
    }

    /// Фигура ленты: верхняя кромка слева направо, нижняя — обратно.
    ///
    /// Толщина в точке это произведение трёх множителей: затухание к краям
    /// пузыря, набегающая волна утолщения и громкость. В тишине лента почти
    /// нитка, на громком звуке занимает больше половины высоты — тот же разброс
    /// 7…75 px, что и на записи.
    fileprivate func ribbon(in size: CGSize, layer: AuroraLayer, time: Double) -> Path {
        let steps = 72
        var top: [CGPoint] = []
        var bottom: [CGPoint] = []
        top.reserveCapacity(steps + 1)
        bottom.reserveCapacity(steps + 1)

        // Тот же уровень, что красит слои: толщина и яркость должны ходить
        // вместе, иначе лента то толстая и тусклая, то тонкая и яркая.
        let loudness = drive(at: time)

        for step in 0...steps {
            let ratio = Double(step) / Double(steps)
            let x = size.width * ratio

            // Концы ленты уходят в ничто: у пузыря скруглённые бока, и прямой
            // обрубок об них читается как ошибка отрисовки.
            let envelope = pow(sin(ratio * .pi), 1.6)

            let centre = size.height * (0.5 + layer.offset)
                + sin(ratio * .pi * 2 * layer.frequency + time * layer.speed * 2)
                * size.height * layer.swing * envelope * loudness

            // Два набегания с разной скоростью — с одним утолщение ходило бы
            // маятником, а на записи оно переезжает неравномерно.
            // Набухание бежит вдоль оси и **успевает пройти полный цикл**:
            // при прежней скорости период выходил около 1.6 с, у референса —
            // 0.65 с. Отсюда множитель 2.4.
            let pace = time * layer.swellSpeed * 2.4
            let travel = sin(ratio * .pi * 2 - pace)
                + 0.6 * sin(ratio * .pi * 3.4 + pace * 0.7)
            let swell = 1 + layer.swell * travel / 1.6

            let half = size.height * layer.thickness / 2
                * envelope * loudness * max(0.12, swell)

            top.append(CGPoint(x: x, y: centre - half))
            bottom.append(CGPoint(x: x, y: centre + half))
        }

        var path = Path()
        path.addLines(top)
        path.addLines(bottom.reversed())
        path.closeSubpath()
        return path
    }

    /// Положение блика 0…1, ходит туда-сюда, а не прыгает с края на край.
    private func shinePosition(at time: Double) -> Double {
        0.5 + 0.45 * sin(time * 1.5)
    }
}

/// Форма шара: почти эллипс, но со слегка приплюснутыми боками — как в
/// макете. Скругление берём от меньшей стороны, чтобы пропорция не ломала его.
private struct OrbShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: rect.height * 0.5, style: .continuous).path(in: rect)
    }
}

/// Сам пузырь внутри кадра. Он заметно меньше кадра: на растре из макета тело
/// занимает 783 × 573 из 1024 × 822, а картинка ещё и растянута по высоте на
/// 124.3 % и поднята на 15.9 %. Отсюда доли ниже — они пересчитаны из этих
/// чисел и сходятся с замером по рендеру.
///
/// Знать их обязательно: и лента, и свечение кромки, нарисованные по краю
/// кадра, оказываются вокруг пустоты, а не вокруг пузыря. На тихом звуке это
/// незаметно, на громком читается как лишняя рамка вокруг шара.
enum OrbBubble {
    static let left = 0.115
    static let width = 0.764
    static let top = 0.063
    static let height = 0.865

    static func rect(in size: CGSize) -> CGRect {
        CGRect(x: size.width * left, y: size.height * top,
               width: size.width * width, height: size.height * height)
    }
}

private struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let bubble = OrbBubble.rect(in: rect.size).offsetBy(dx: rect.minX, dy: rect.minY)
        return RoundedRectangle(cornerRadius: bubble.height * 0.5, style: .continuous)
            .path(in: bubble)
    }
}
