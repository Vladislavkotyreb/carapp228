import SwiftUI

enum AppColors {
    static let accent = Color("AccentColor", bundle: nil)
    static let primary = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let secondary = Color(red: 0.45, green: 0.45, blue: 0.47)
    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let danger = Color.red
}

enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum AppTypography {
    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title = Font.title2.weight(.semibold)
    static let body = Font.body
    static let caption = Font.caption
}

struct Theme {
    static let cornerRadius: CGFloat = 12
    static let buttonHeight: CGFloat = 52
}

/// Значения один-в-один из Figma (Beepy, секция «1 флоу: онбординг + добавление машины»).
/// Не заменять токенами AppColors/AppSpacing — там другие значения.
enum Figma {
    // Variables
    static let backgroundsPrimary = Color.white                                     // Backgrounds/Primary #FFFFFF
    static let labelsPrimary = Color.black                                          // Labels/Primary #000000
    static let graysGray = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255) // Grays/Gray #8E8E93
    static let labelsTertiary = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255)
        .opacity(0.3)                                                               // Labels/Tertiary
    static let vibrantControlsPrimary = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255) // #1A1A1A
    static let fillsTertiary = Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255)
        .opacity(0.12)                                                              // Fills/Tertiary
    static let labelsQuaternary = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255)
        .opacity(0.18)                                                              // Labels/Quaternary
    static let accentsRed = Color(red: 1, green: 56 / 255, blue: 60 / 255)           // Accents/Red #FF383C
    static let accentsBlue = Color(red: 0, green: 136 / 255, blue: 1)                // Accents/Blue #0088FF
    static let separatorsVibrant = Color(red: 230 / 255, green: 230 / 255, blue: 230 / 255) // #E6E6E6
    static let labelsVibrantTertiary = Color(red: 191 / 255, green: 191 / 255, blue: 191 / 255) // #BFBFBF
    static let overlaysDefault = Color.black.opacity(0.2)                           // Overlays/Default
    static let vibrantSecondary = Color(red: 114 / 255, green: 114 / 255, blue: 114 / 255)  // #727272
    static let grabber = Color(red: 204 / 255, green: 204 / 255, blue: 204 / 255)    // #CCCCCC
    static let fillsPrimary = Color(red: 120 / 255, green: 120 / 255, blue: 120 / 255)
        .opacity(0.2)                                                               // Fills/Primary
    static let fillsQuaternary = Color(red: 116 / 255, green: 116 / 255, blue: 128 / 255)
        .opacity(0.08)                                                              // Fills/Quaternary
    static let fillsVibrantSecondary = Color(red: 224 / 255, green: 224 / 255, blue: 224 / 255) // #E0E0E0
    static let graysGray2 = Color(red: 174 / 255, green: 174 / 255, blue: 178 / 255) // Grays/Gray-2 #AEAEB2
    static let graysBlack = Color.black                                              // Grays/Black
    // Цвета живого шара на экране «Ошибки». В макете он растровая заглушка,
    // поэтому взяты с неё пипеткой.
    static let orbGreen = Color(red: 88 / 255, green: 240 / 255, blue: 168 / 255)
    static let orbTeal = Color(red: 64 / 255, green: 210 / 255, blue: 224 / 255)
    static let orbViolet = Color(red: 132 / 255, green: 116 / 255, blue: 232 / 255)
    // Палитра живой волны снята пипеткой с самого ассета из макета
    // (нода 46102:2999), чтобы анимация продолжала ровно его цвета.
    static let orbCore = Color(red: 144 / 255, green: 251 / 255, blue: 244 / 255)
    static let orbBody = Color(red: 87 / 255, green: 200 / 255, blue: 179 / 255)
    static let orbDeep = Color(red: 50 / 255, green: 144 / 255, blue: 105 / 255)
    /// Середина ленты на референсной записи: между бирюзовой кромкой сверху и
    /// зелёным телом снизу. Снято с кадра x=120, y=86.
    static let orbMint = Color(red: 117 / 255, green: 247 / 255, blue: 148 / 255)
    /// Низ ленты. Тот же кадр, y=110 — здесь бирюзы уже нет вовсе.
    static let orbGrass = Color(red: 79 / 255, green: 174 / 255, blue: 105 / 255)

    /// Тон облака частиц. У автора демо фиолетовый на белом фоне; у нас фон
    /// чёрный, поэтому взят светлее — исходный на нём проваливается.
    static let orbParticle = Color(red: 155 / 255, green: 140 / 255, blue: 255 / 255)
    static let darkCard = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)      // #1A1A1A
    static let accentsGreen = Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255) // Accents/Green #34C759
    static let fillsSecondary = Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255)
        .opacity(0.16)                                                              // Fills/Secondary
    static let trackBackground = Color(red: 120 / 255, green: 120 / 255, blue: 120 / 255)
        .opacity(0.4)                                                               // Track прогресса ТО
    static let vibrantPrimary = Color(red: 204 / 255, green: 204 / 255, blue: 204 / 255) // Fills-Vibrant/Primary #CCC

    /// База под градиентом главного экрана (node 45879:3002).
    static let mainBackground = Color(red: 242 / 255, green: 242 / 255, blue: 247 / 255) // #F2F2F7

    /// Высота градиентного слоя: 52.98% от контейнера 1763.
    /// Высота градиентного блока: точка, где фон становится полностью светлым.
    static let mainGradientHeight: CGFloat = 656

    /// Фон главного экрана: чёрный сверху → #F2F2F7 снизу, пинится к верху экрана.
    ///
    /// Стопы сняты с отрисовки **экрана** (нода 45867:3007), а не с ноды
    /// градиента и тем более не по CSS. Причин две: слоёв там теперь два и
    /// экспорт не отдаёт ни прозрачности, ни режима наложения; и сам инстанс
    /// градиента на экране другого размера, чем компонент, — пересчёт через
    /// ноду промахнулся на 200pt. Экран — единственный надёжный источник.
    ///
    /// Переход стал заметно короче прежнего: чёрное держится до y = 367,
    /// полностью светлым фон становится к y = 656.
    ///
    /// Точного совпадения тут не будет: SwiftUI смешивает цвета не в том же
    /// пространстве, что Figma, и тёмная часть тянется чуть дольше. Попытка
    /// скомпенсировать сдвигом стопов на 12pt сделала хуже (22.1 против 21.3),
    /// поэтому стопы стоят там, где они на рендере.
    static let mainGradient = LinearGradient(
        stops: [
            .init(color: Color(red: 242 / 255, green: 242 / 255, blue: 247 / 255), location: 0.0008),
            .init(color: Color(red: 241 / 255, green: 241 / 255, blue: 245 / 255), location: 0.0168),
            .init(color: Color(red: 236 / 255, green: 236 / 255, blue: 241 / 255), location: 0.0259),
            .init(color: Color(red: 229 / 255, green: 229 / 255, blue: 234 / 255), location: 0.0616),
            .init(color: Color(red: 220 / 255, green: 220 / 255, blue: 224 / 255), location: 0.0805),
            .init(color: Color(red: 208 / 255, green: 208 / 255, blue: 212 / 255), location: 0.1128),
            .init(color: Color(red: 194 / 255, green: 194 / 255, blue: 198 / 255), location: 0.1936),
            .init(color: Color(red: 178 / 255, green: 178 / 255, blue: 182 / 255), location: 0.2175),
            .init(color: Color(red: 160 / 255, green: 160 / 255, blue: 164 / 255), location: 0.2293),
            .init(color: Color(red: 141 / 255, green: 141 / 255, blue: 144 / 255), location: 0.2402),
            .init(color: Color(red: 120 / 255, green: 120 / 255, blue: 123 / 255), location: 0.2584),
            .init(color: Color(red: 98 / 255, green: 98 / 255, blue: 100 / 255), location: 0.284),
            .init(color: Color(red: 75 / 255, green: 75 / 255, blue: 76 / 255), location: 0.3163),
            .init(color: Color(red: 50 / 255, green: 50 / 255, blue: 52 / 255), location: 0.3567),
            .init(color: Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255), location: 0.3973),
            .init(color: .black, location: 0.4405)
        ],
        startPoint: .bottom,
        endPoint: .top
    )

    // Frame макета — iPhone 16 Pro, 402×874
    static let frameWidth: CGFloat = 402
    static let frameHeight: CGFloat = 874
    /// Высота шапки при прокрутке (нода 46012:1815). В макете шапка нарисована
    /// от самого верха кадра, то есть вместе со статус-баром — как и остальные
    /// верхние координаты экрана, отсчитывается от края, а не от safe area.
    /// Было 137 с номером внутри; дизайн ужал её до компактной строки.
    static let scrollHeaderHeight: CGFloat = 86
    /// Нижняя safe area на макетном устройстве. В самом Figma её нет —
    /// макет нарисован до края экрана, поэтому нижние элементы в нём
    /// местами заезжают на home indicator.
    static let frameSafeBottom: CGFloat = 34
    /// Минимальный зазор до home indicator. 7pt — столько макет оставляет таббару,
    /// то есть это и есть заданный дизайном минимум.
    static let minBottomGap: CGFloat = 7

    /// Сколько отступить от нижней границы safe area для элемента, который
    /// в макете стоит на `y` и имеет высоту `height`. Там, где макет уже
    /// уважает индикатор, отступ сохраняется как есть; где заезжает —
    /// поднимаем до минимального.
    static func bottomGap(y: CGFloat, height: CGFloat) -> CGFloat {
        max(frameHeight - frameSafeBottom - y - height, minBottomGap)
    }

    // Типографика
    static let titleSize: CGFloat = 32
    static let titleLineHeight: CGFloat = 38.4   // 32 × 1.2
    static let bodySize: CGFloat = 20
    static let bodyLineHeight: CGFloat = 27
    static let bodyTracking: CGFloat = -0.45
    static let buttonLabelSize: CGFloat = 17
}

/// Метрики экрана. Заполняются одним GeometryReader на уровне приложения.
/// Читать окно UIKit прямо в body нельзя: body начинает зависеть от размера
/// окна, а тот — от раскладки этого же body, и AttributeGraph ловит цикл.
@MainActor
final class DeviceMetrics: ObservableObject {
    @Published private(set) var safeBottom: CGFloat = Figma.frameSafeBottom
    @Published private(set) var height: CGFloat = Figma.frameHeight

    func update(size: CGSize, insets: EdgeInsets) {
        let fullHeight = size.height + insets.top + insets.bottom
        if safeBottom != insets.bottom { safeBottom = insets.bottom }
        if height != fullHeight { height = fullHeight }
    }

    /// Координата y от верха экрана для элемента, прижатого к нижней safe area.
    func bottomAnchoredY(designY: CGFloat, height elementHeight: CGFloat) -> CGFloat {
        height - safeBottom - Figma.bottomGap(y: designY, height: elementHeight) - elementHeight
    }
}

extension View {
    /// Догоняет line-height из Figma. Figma раскидывает лишний интервал поровну сверху и снизу
    /// каждой строки, SwiftUI добавляет его только между строками — поэтому ещё и сдвигаем
    /// блок вниз на половину разницы, иначе первая строка встаёт на ~2pt выше макета.
    func figmaLineHeight(_ target: CGFloat, fontSize: CGFloat, weight: UIFont.Weight = .regular) -> some View {
        let delta = max(0, target - UIFont.systemFont(ofSize: fontSize, weight: weight).lineHeight)
        return lineSpacing(delta).padding(.top, delta / 2)
    }

    /// Ставит блок в координаты макета (frame 402×874): x/ширина как в Figma, y — от верха экрана.
    func figmaBlock(x: CGFloat, width: CGFloat, y: CGFloat) -> some View {
        padding(.leading, x)
            .padding(.trailing, Figma.frameWidth - x - width)
            .frame(maxWidth: .infinity)
            .offset(y: y)
    }
}
