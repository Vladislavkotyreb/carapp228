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
    static let overlaysDefault = Color.black.opacity(0.2)                           // Overlays/Default
    static let vibrantSecondary = Color(red: 114 / 255, green: 114 / 255, blue: 114 / 255)  // #727272
    static let grabber = Color(red: 204 / 255, green: 204 / 255, blue: 204 / 255)    // #CCCCCC
    static let fillsPrimary = Color(red: 120 / 255, green: 120 / 255, blue: 120 / 255)
        .opacity(0.2)                                                               // Fills/Primary
    static let fillsQuaternary = Color(red: 116 / 255, green: 116 / 255, blue: 128 / 255)
        .opacity(0.08)                                                              // Fills/Quaternary
    static let fillsVibrantSecondary = Color(red: 224 / 255, green: 224 / 255, blue: 224 / 255) // #E0E0E0
    static let graysGray2 = Color(red: 174 / 255, green: 174 / 255, blue: 178 / 255) // Grays/Gray-2 #AEAEB2
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
    static let mainGradientHeight: CGFloat = 934

    /// Фон главного экрана: чёрный сверху → #F2F2F7 снизу, пинится к верху экрана.
    static let mainGradient = LinearGradient(
        stops: [
            .init(color: Color(red: 242 / 255, green: 242 / 255, blue: 247 / 255), location: 0.13544),
            .init(color: Color(red: 241 / 255, green: 241 / 255, blue: 245 / 255), location: 0.18833),
            .init(color: Color(red: 236 / 255, green: 236 / 255, blue: 241 / 255), location: 0.22785),
            .init(color: Color(red: 229 / 255, green: 229 / 255, blue: 234 / 255), location: 0.25677),
            .init(color: Color(red: 220 / 255, green: 220 / 255, blue: 224 / 255), location: 0.27784),
            .init(color: Color(red: 208 / 255, green: 208 / 255, blue: 212 / 255), location: 0.29385),
            .init(color: Color(red: 194 / 255, green: 194 / 255, blue: 198 / 255), location: 0.30754),
            .init(color: Color(red: 178 / 255, green: 178 / 255, blue: 182 / 255), location: 0.32168),
            .init(color: Color(red: 160 / 255, green: 160 / 255, blue: 164 / 255), location: 0.33905),
            .init(color: Color(red: 141 / 255, green: 141 / 255, blue: 144 / 255), location: 0.36239),
            .init(color: Color(red: 120 / 255, green: 120 / 255, blue: 123 / 255), location: 0.39448),
            .init(color: Color(red: 98 / 255, green: 98 / 255, blue: 100 / 255), location: 0.43808),
            .init(color: Color(red: 75 / 255, green: 75 / 255, blue: 76 / 255), location: 0.49595),
            .init(color: Color(red: 50 / 255, green: 50 / 255, blue: 52 / 255), location: 0.57086),
            .init(color: Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255), location: 0.66557),
            .init(color: .black, location: 0.78285)
        ],
        startPoint: .bottom,
        endPoint: .top
    )

    // Frame макета
    static let frameWidth: CGFloat = 402

    // Типографика
    static let titleSize: CGFloat = 32
    static let titleLineHeight: CGFloat = 38.4   // 32 × 1.2
    static let bodySize: CGFloat = 20
    static let bodyLineHeight: CGFloat = 27
    static let bodyTracking: CGFloat = -0.45
    static let buttonLabelSize: CGFloat = 17
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
