import SwiftUI

/// Живой шар с экрана «Ошибки» (нода `46100:2764`). В макете это растровая
/// заглушка, поэтому рисуем сами.
///
/// Через `Canvas` и `TimelineView`, а не `MeshGradient`: последний требует
/// iOS 18, а таргет проекта 17.0. Заодно волной можно управлять точно —
/// mesh пришлось бы подгонять контрольными точками.
/// Какой шар рисуем. Переключается одной константой ниже. Стили `.wave`,
/// `.blob` и `.particles` удалены 08.10.2026: с сентября они не включались.
enum OrbStyle: String {
    /// Растр из макета плюс живая волна поверх. В покое совпадает с Figma
    /// точь в точь, потому что это буквально тот же файл.
    case figma
    /// Облачко: тёмная пилюля с волной Siri (`SoundCapsule`). Волна — перенос
    /// кривой iOS 9 из siriwave (MIT), вид — с записи экрана пользователя
    /// от 06.10.2026.
    case cloud
}

struct SoundOrb: View {
    /// Единственное место переключения. Прежний шар из макета — `.figma`:
    /// одно слово ниже.
    static let style: OrbStyle = {
        #if DEBUG
        // Съёмка вариантов без пересборки:
        // `SIMCTL_CHILD_BEEPY_ORB=figma xcrun simctl launch …`
        if let raw = ProcessInfo.processInfo.environment["BEEPY_ORB"],
           let style = OrbStyle(rawValue: raw) {
            return style
        }
        #endif
        return .cloud
    }()

    /// Громкость для съёмки: в симуляторе микрофон молчит, и вид «в полный
    /// голос» иначе не снять. `SIMCTL_CHILD_BEEPY_ORB_LEVEL=0.8`, только DEBUG.
    private static let fixedLevel: Double? = {
        #if DEBUG
        ProcessInfo.processInfo.environment["BEEPY_ORB_LEVEL"].flatMap(Double.init)
        #else
        nil
        #endif
    }()

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
    /// Верхняя граница **намеренно не 1.0**. Она там была, и это ломало
    /// главное: на пиках дыхания шар уже стоял на максимуме, и звук поверх не
    /// мог добавить ничего. В промежутках требовался уровень выше 0.36 —
    /// больше, чем даёт обычная речь. Шар выглядел живым и при этом полностью
    /// глухим к микрофону.
    ///
    /// Замер с микрофона: речь даёт 0.13…0.73. Чтобы она была видна, дыхание
    /// должно жить **ниже** этого коридора и оставлять запас сверху.
    static let idleLow: Double = 0.26
    static let idleHigh: Double = 0.52

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
        // Усиление 2.0, а не 1.6: при замеренных 0.13…0.73 речь тогда
        // перекрывает верх дыхания уже с 0.26 и растёт до потолка к 0.5.
        // Живость в тишине держит не размах, а скорость набухания — она
        // осталась прежней.
        // Уровень уже приведён к 0…1 над фоном, поэтому усиление тут скромное.
        return max(idle, min(1, level * 1.15))
    }

    var body: some View {
        switch Self.style {
        case .figma: figmaOrb
        case .cloud: SoundCapsule(level: Self.fixedLevel ?? level)
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

    /// При Reduce Motion время замирает — остаётся тот же градиент, но
    /// неподвижный. Требование HIG, так же сделано у блика на кромке.
    private func phase(at date: Date) -> Double {
        reduceMotion ? 0 : date.timeIntervalSinceReferenceDate
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
