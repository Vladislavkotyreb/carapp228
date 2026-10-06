import Foundation

/// Облачко прослушивания: капсула из стекла, внутри волна или «фары».
///
/// Здесь всё, что решается без SwiftUI: форма капсулы, волна, моргание,
/// настроения фар и палитры. Рисует `SoundCapsule`. Рисунок и код свои —
/// не перенос облачка No Tipe: их лицензия запрещает и копию, и перевод.
/// Живое демо того же рисунка — https://claude.ai/artifact/9Lbsedthv427weUeWY6zyC

/// Цвет как три доли 0…1. Свой тип, а не `Color`, — чтобы смешивать палитру
/// с янтарём «стука» и проверять это здесь, без SwiftUI.
struct CloudRGB: Equatable {
    let r: Double
    let g: Double
    let b: Double

    /// Каналы в привычных 0…255, как их снимают пипеткой.
    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r / 255
        self.g = g / 255
        self.b = b / 255
    }

    private init(unit r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    func mixed(with other: CloudRGB, _ t: Double) -> CloudRGB {
        let k = min(1, max(0, t))
        // Вид a·(1−k) + b·k, а не a + (b − a)·k: при k = 1 он даёт ровно b,
        // без хвоста округления, и янтарь «стука» совпадает с образцом.
        return CloudRGB(unit: r * (1 - k) + other.r * k,
                        g * (1 - k) + other.g * k,
                        b * (1 - k) + other.b * k)
    }
}

/// Палитры облачка. Aurora продолжает зелёный шар из макета, Prism — вторая,
/// фиолетово-синяя с розовым.
enum CloudPalette: String, CaseIterable {
    case aurora
    case prism

    /// Дальняя широкая лента — цветовое пятно без формы.
    var deep: CloudRGB {
        switch self {
        case .aurora: CloudRGB(40, 150, 120)
        case .prism: CloudRGB(90, 120, 255)
        }
    }

    /// Средняя лента.
    var mid: CloudRGB {
        switch self {
        case .aurora: CloudRGB(60, 200, 215)
        case .prism: CloudRGB(255, 95, 175)
        }
    }

    /// Основное свечение: ядро волны, ободок, отсвет на дне капсулы.
    var glow: CloudRGB {
        switch self {
        case .aurora: CloudRGB(70, 220, 160)
        case .prism: CloudRGB(150, 105, 255)
        }
    }

    /// Белая сердцевина ядра.
    var core: CloudRGB {
        switch self {
        case .aurora: CloudRGB(215, 255, 238)
        case .prism: CloudRGB(238, 228, 255)
        }
    }

    /// Ходовые огни и кромка фар.
    var led: CloudRGB {
        switch self {
        case .aurora: CloudRGB(150, 255, 215)
        case .prism: CloudRGB(200, 180, 255)
        }
    }

    /// Цвет тревоги: в «стуке» фары уходят в янтарь, как поворотник.
    static let amber = CloudRGB(255, 178, 64)
}

/// Что выражают фары.
enum CloudMood: String, CaseIterable {
    /// Идёт запись: взгляд гуляет за звуком, свечение дышит громкостью.
    case listen
    /// Тишина перед записью.
    case quiet
    /// Нашлась неисправность: фары хмурятся, вздрагивают и желтеют.
    case knock
    /// Ничего тревожного: фары щурятся дугой.
    case ok
    /// Пауза: веки почти закрыты.
    case sleep
}

/// Параметры фар. Настроение — это набор чисел, а не ветка в отрисовке:
/// между двумя наборами можно плавно перейти, и смена выглядит как мимика,
/// а не как подмена картинки.
struct CloudFace: Equatable {
    /// Раскрытие век, 0…1.
    var open: Double
    /// Насколько опущены внутренние углы — «нахмуренность».
    var tilt: Double
    /// 1 — фары превращаются в дуги «всё хорошо».
    var happy: Double
    /// Яркость свечения.
    var dim: Double
    /// Доля янтаря в цвете.
    var amber: Double
    /// Насколько взгляд гуляет.
    var look: Double

    static func of(_ mood: CloudMood) -> CloudFace {
        switch mood {
        case .listen: CloudFace(open: 1, tilt: 0, happy: 0, dim: 1, amber: 0, look: 1)
        case .quiet: CloudFace(open: 0.86, tilt: 0, happy: 0, dim: 0.72, amber: 0, look: 0.4)
        case .knock: CloudFace(open: 0.62, tilt: 0.42, happy: 0, dim: 1.05, amber: 1, look: 0.3)
        case .ok: CloudFace(open: 1, tilt: 0, happy: 1, dim: 1, amber: 0, look: 0)
        case .sleep: CloudFace(open: 0.18, tilt: -0.08, happy: 0, dim: 0.35, amber: 0, look: 0)
        }
    }

    func mixed(with other: CloudFace, _ t: Double) -> CloudFace {
        let k = min(1, max(0, t))
        func mix(_ a: Double, _ b: Double) -> Double { a * (1 - k) + b * k }
        return CloudFace(open: mix(open, other.open), tilt: mix(tilt, other.tilt),
                         happy: mix(happy, other.happy), dim: mix(dim, other.dim),
                         amber: mix(amber, other.amber), look: mix(look, other.look))
    }
}

enum CloudMath {
    /// Капсула шире высоты в 1.55 раза — та же пропорция, что у шара в макете
    /// (370 × 238.955), чтобы облачко встало на его место без правок вёрстки.
    static let aspect: Double = 1.55

    /// Показатель суперэллипса: мягче прямоугольника со скруглением, строже
    /// овала. 2 — эллипс, чем больше, тем ближе к прямоугольнику.
    static let squircle: Double = 3.4

    /// Точка контура капсулы с центром в нуле: полуоси `a` и `b`, угол 0…2π.
    static func capsulePoint(_ angle: Double, a: Double, b: Double,
                             n: Double = squircle) -> (x: Double, y: Double) {
        let c = cos(angle), s = sin(angle)
        let x = a * signum(c) * pow(abs(c), 2 / n)
        let y = b * signum(s) * pow(abs(s), 2 / n)
        return (x, y)
    }

    /// Волна гаснет к краям капсулы, иначе ленты упираются в стекло обрубками.
    static func envelope(_ u: Double) -> Double {
        pow(sin(Double.pi * min(1, max(0, u))), 1.6)
    }

    /// Отклонение ленты от средней линии, −1…1, в точке `u` (0 — левый край,
    /// 1 — правый). Две синусоиды с несоизмеримыми частотами, чтобы рисунок
    /// не повторялся заметным периодом.
    static func wave(_ u: Double, time: Double, k: Double, speed: Double, phase: Double) -> Double {
        let x = k * u * 2 * Double.pi
        return envelope(u) * (0.62 * sin(x + time * speed + phase)
                              + 0.38 * sin(1.73 * x - time * speed * 0.8 + phase * 2))
    }

    /// Уровень, которым живёт облачко: в тишине дышит само между 0.22 и 0.38,
    /// с голосом мотора идёт за ним. Мёртвая картинка на экране прослушивания
    /// читается как сломанная — тот же довод, что у `SoundOrb.drive`.
    static func drive(level: Double, at time: Double) -> Double {
        let breath = (0.6 * sin(time * 1.3) + 0.4 * sin(time * 3.1 + 1.2) + 1) / 2
        let idle = 0.22 + 0.16 * breath
        return max(idle, min(1, level))
    }

    /// Раскрытие век с учётом моргания: 1 — открыты, 0.12 — на дне моргания.
    /// Моргание раз в 3.6 с плюс `seed`, длится 0.18 с.
    static func blink(at time: Double, seed: Double = 0) -> Double {
        let period = 3.6 + seed
        var phase = fmod(time + seed * 1.7, period)
        if phase < 0 { phase += period }
        let distance = abs(phase / period - 0.5) * period
        return distance < 0.09 ? 0.12 + distance / 0.09 * 0.88 : 1
    }

    /// Куда смотрят фары, −1…1. Чем громче, тем шире гуляет взгляд.
    static func gaze(at time: Double, level: Double) -> Double {
        (0.55 * sin(time * 0.9) + 0.45 * sin(time * 2.3 + 1)) * (0.4 + 0.6 * level)
    }

    /// Ход смены настроения: 0…1 за 0.35 с, мягко в начале и в конце.
    static func moodProgress(elapsed: Double) -> Double {
        let t = min(1, max(0, elapsed / 0.35))
        return t * t * (3 - 2 * t)
    }
}

private func signum(_ value: Double) -> Double {
    value < 0 ? -1 : (value > 0 ? 1 : 0)
}
