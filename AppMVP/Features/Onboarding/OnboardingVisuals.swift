import SwiftUI

/// Иллюстрации страниц онбординга — фрагменты самого приложения на стекле,
/// по образцу онбординга PARQ на Dribbble (выбор 15.10.2026): тёмный фон,
/// стеклянные карточки, один зелёный акцент для статусов. Картинок нет —
/// всё нарисовано теми же компонентами, что в приложении, и живёт:
/// счётчик километров, полоса ТО, номер набирается по символу.
///
/// Моушн простой и один на всех: карточка поднимается и проявляется,
/// чипы плавно проявляются следом, без постоянного покачивания. С «Уменьшением
/// движения» остаётся только проявление — этого требует HIG.
enum OnboardingFeature: CaseIterable {
    case trips, sound, service, plate
}

struct OnboardingVisual: View {
    let feature: OnboardingFeature

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Карточка на месте.
    @State private var shown = false
    /// Чипы на месте — чуть позже карточки.
    @State private var chips = false

    private enum Layout {
        static let rise: CGFloat = 12
        static let chipDelay = 0.12
        static let secondChipDelay = 0.08
        static let carHeight: CGFloat = 230
        static let cardRadius: CGFloat = 36
    }

    var body: some View {
        glassContent
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : Layout.rise)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(reduceMotion ? Motion.fade : Motion.onboardingReveal) { shown = true }
                withAnimation(reduceMotion ? Motion.fade : Motion.onboardingReveal.delay(Layout.chipDelay)) { chips = true }
            }
    }

    @ViewBuilder
    private var glassContent: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { content }
        } else {
            content
        }
    }

    // Decode once, outside repeated body evaluations during transitions.
    private static let carImage: UIImage? = {
        guard let url = Bundle.main.url(forResource: "toyota-camry-70", withExtension: "heic",
                                       subdirectory: "CarCatalog") else { return nil }
        return UIImage(contentsOfFile: url.path)?.preparingForDisplay()
    }()

    @ViewBuilder
    private var content: some View {
        switch feature {
        case .trips: trips
        case .sound: sound
        case .service: service
        case .plate: plate
        }
    }

    // MARK: - Автопробег

    @State private var km = 0

    private var trips: some View {
        ZStack {
            // Настоящая машина из каталога, а не «машина под чехлом» —
            // та остаётся приветствию. Camry XV70 — самая узнаваемая.
            Group {
                if let image = Self.carImage {
                    Image(uiImage: image).resizable()
                } else {
                    Image("CarPhoto").resizable()
                }
            }
            .scaledToFit()
            .frame(height: Layout.carHeight)

            VStack {
                HStack {
                    chip(dot: Figma.accentsGreen, text: "Поездка идёт")
                        .modifier(ChipEntry(on: chips, reduceMotion: reduceMotion))
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    chip(icon: "point.topleft.down.to.point.bottomright.curvepath",
                         text: "+\(km)\u{00A0}км к\u{00A0}пробегу")
                        .contentTransition(.numericText(value: Double(km)))
                        .modifier(ChipEntry(on: chips, reduceMotion: reduceMotion, delay: Layout.secondChipDelay))
                }
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7).delay(Layout.chipDelay)) { km = 12 }
        }
    }

    // MARK: - Диагностика

    private var sound: some View {
        ZStack {
            SoundOrb(level: 0)
                .aspectRatio(SoundOrb.aspectRatio, contentMode: .fit)

            VStack {
                HStack {
                    chip(dot: Figma.accentsYellow, text: "Слушаю мотор")
                        .modifier(ChipEntry(on: chips, reduceMotion: reduceMotion))
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    chip(icon: "iphone", text: "Разбор на\u{00A0}телефоне")
                        .modifier(ChipEntry(on: chips, reduceMotion: reduceMotion, delay: Layout.secondChipDelay))
                }
            }
        }
    }

    // MARK: - ТО

    @State private var left = ServiceMath.interval
    @State private var progress = 0.0

    private var service: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Text("ТО через")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Figma.graysGray2)
                Text("\(NumberFormat.grouped(left))\u{00A0}км")
                    .font(.system(size: 28, weight: .bold))
                    // Цифры одной ширины: иначе на переходе 10 000 → 4 999
                    // строка меняла ширину и «км» прыгал.
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(left)))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Figma.trackBackground)
                        Capsule().fill(Figma.accentsYellow)
                            .frame(width: max(30, geo.size.width * progress))
                    }
                }
                .frame(height: 30)
                Text("Осталось меньше 5\u{00A0}000\u{00A0}км")
                    .font(.system(size: 15))
                    .foregroundStyle(Figma.labelsSecondary)
                    .opacity(chips ? 1 : 0)
            }
            .padding(24)
            .liquidGlass(in: RoundedRectangle(cornerRadius: Layout.cardRadius)) {
                RoundedRectangle(cornerRadius: Layout.cardRadius).fill(Material.regular)
            }

            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                Text("Записаться на\u{00A0}ТО")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundStyle(Figma.labelsPrimary)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .liquidGlass(in: Capsule()) { Capsule().fill(Material.regular) }
            .modifier(ChipEntry(on: chips, reduceMotion: reduceMotion, delay: Layout.secondChipDelay))
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7).delay(Layout.chipDelay)) {
                left = 4_999
                progress = 0.5
            }
        }
    }

    // MARK: - Госномер

    @State private var typed = ""
    private static let demoPlate = "В777ОР777"

    private var plate: some View {
        VStack(spacing: 20) {
            PlateInputField(text: .constant(typed))
                .allowsHitTesting(false)
                .overlay { ScanCorners().opacity(chips ? 1 : 0) }

            HStack {
                chip(dot: Figma.accentsGreen, text: "Нашли: Kia Rio, 2019")
                    .opacity(typed.count == Self.demoPlate.count ? 1 : 0)
                    .scaleEffect(typed.count == Self.demoPlate.count || reduceMotion ? 1 : 0.9)
                    .animation(.spring(response: 0.45, dampingFraction: 0.7), value: typed)
                Spacer()
            }
        }
        .task {
            // Символы по одному, как будто человек набирает номер.
            if reduceMotion {
                typed = Self.demoPlate
                return
            }
            try? await Task.sleep(for: .milliseconds(450))
            for character in Self.demoPlate {
                guard !Task.isCancelled else { return }
                typed.append(character)
                try? await Task.sleep(for: .milliseconds(110))
            }
        }
    }

    // MARK: - Чип

    private func chip(dot: Color? = nil, icon: String? = nil, text: String) -> some View {
        HStack(spacing: 6) {
            if let dot {
                Circle().fill(dot).frame(width: 7, height: 7)
            }
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Figma.accentsGreen)
            }
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Figma.labelsPrimary)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .liquidGlass(in: Capsule()) { Capsule().fill(Material.regular) }
    }
}

/// Один вход чипа, без второй пружины и бесконечного покачивания.
private struct ChipEntry: ViewModifier {
    let on: Bool
    let reduceMotion: Bool
    var delay = 0.0

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(y: reduceMotion || on ? 0 : 8)
            .animation(reduceMotion ? Motion.fade : Motion.onboardingReveal.delay(delay), value: on)
    }
}

/// Уголки распознавания вокруг номерной рамки — как в PARQ.
private struct ScanCorners: View {
    var body: some View {
        GeometryReader { geo in
            let r: CGFloat = 26, l: CGFloat = 22, inset: CGFloat = -8
            Path { p in
                let w = geo.size.width - 2 * inset, h = geo.size.height - 2 * inset
                let o = CGPoint(x: inset, y: inset)
                // Четыре угла: короткие отрезки с дугой.
                for (sx, sy) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)] {
                    let cx = o.x + sx * w, cy = o.y + sy * h
                    let dx: CGFloat = sx == 0 ? 1 : -1, dy: CGFloat = sy == 0 ? 1 : -1
                    p.move(to: CGPoint(x: cx, y: cy + dy * (r + l)))
                    p.addLine(to: CGPoint(x: cx, y: cy + dy * r))
                    p.addQuadCurve(to: CGPoint(x: cx + dx * r, y: cy), control: CGPoint(x: cx, y: cy))
                    p.addLine(to: CGPoint(x: cx + dx * (r + l), y: cy))
                }
            }
            .stroke(Figma.accentsGreen, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }
}

/// Заголовок и описание страницы всплывают следом за иллюстрацией.
struct OnboardingRise: ViewModifier {
    var delay = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(reduceMotion ? Motion.fade : Motion.onboardingReveal.delay(delay)) { shown = true }
            }
    }
}
