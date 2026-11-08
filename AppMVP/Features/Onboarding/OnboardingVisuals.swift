import SwiftUI

// Оригинальные иллюстрации Beepy по композиционным референсам CRED / untitled / komoot.
enum OnboardingFeature { case plate, sound, trips }

struct OnboardingVisual: View {
    let feature: OnboardingFeature
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private static let car: UIImage? = {
        guard let url = Bundle.main.url(forResource: "toyota-camry-70", withExtension: "heic", subdirectory: "CarCatalog") else { return nil }
        return UIImage(contentsOfFile: url.path)?.preparingForDisplay()
    }()

    var body: some View {
        switch feature {
        case .plate: car
        case .sound: wave
        case .trips: route
        }
    }

    private var car: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                Text("А 777 АА")
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    Text("777").font(.system(size: 20, weight: .semibold, design: .monospaced))
                    Text("RUS").font(.system(size: 9, weight: .medium))
                }
            }
            .padding(18)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 20)) {
                RoundedRectangle(cornerRadius: 20).fill(Material.regular)
            }
            Group {
                if let image = Self.car { Image(uiImage: image).resizable() }
                else { Image("CarPhoto").resizable() }
            }
            .scaledToFit()
            .frame(maxHeight: .infinity)
        }
        .padding(.top, 16)
    }

    private var wave: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || scenePhase != .active)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let bars = 49
                let spacing = size.width / CGFloat(bars)
                for index in 0..<bars {
                    let x = Double(index) / Double(bars - 1)
                    let envelope = pow(sin(x * .pi), 1.6)
                    let pulse = 0.35 + 0.65 * abs(sin(Double(index) * 0.62 + time * 2))
                    let height = 6 + CGFloat(envelope * pulse) * size.height * 0.65
                    let rect = CGRect(x: CGFloat(index) * spacing, y: (size.height - height) / 2,
                                      width: max(2, spacing * 0.38), height: height)
                    canvas.fill(Path(roundedRect: rect, cornerRadius: 3),
                                with: .color(Color(red: 0.98, green: 0.44, blue: 0.36)))
                }
            }
        }
        .overlay(alignment: .bottom) {
            Label("Разбор на телефоне", systemImage: "iphone")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
        }
    }

    private var route: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 32)
                    .fill(Color(red: 0.13, green: 0.17, blue: 0.12))
                Canvas { canvas, size in
                    var streets = Path()
                    for index in 0..<8 {
                        let x = CGFloat(index) * size.width / 6
                        streets.move(to: CGPoint(x: x - 60, y: 0))
                        streets.addLine(to: CGPoint(x: x + 70, y: size.height))
                        let y = CGFloat(index) * size.height / 6
                        streets.move(to: CGPoint(x: 0, y: y))
                        streets.addLine(to: CGPoint(x: size.width, y: y - 60))
                    }
                    canvas.stroke(streets, with: .color(.white.opacity(0.07)), lineWidth: 8)
                    var path = Path()
                    let points: [CGPoint] = [CGPoint(x: 0.14, y: 0.78), CGPoint(x: 0.27, y: 0.65),
                        CGPoint(x: 0.47, y: 0.69), CGPoint(x: 0.43, y: 0.44),
                        CGPoint(x: 0.69, y: 0.35), CGPoint(x: 0.82, y: 0.17)]
                    path.addLines(points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
                    canvas.stroke(path, with: .color(.orange.opacity(0.16)), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                    canvas.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
                .clipShape(RoundedRectangle(cornerRadius: 32))
                Circle().fill(.white).frame(width: 12, height: 12)
                    .position(x: width * 0.14, y: height * 0.78)
                Image(systemName: "location.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
                    .background(.white, in: Circle())
                    .position(x: width * 0.82, y: height * 0.17)
                VStack {
                    Spacer()
                    HStack {
                        Label("12,4\u{00A0}км", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        Spacer()
                        Text("24\u{00A0}мин")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(16)
                    .liquidGlass(in: Capsule()) { Capsule().fill(Material.regular) }
                    .padding(16)
                }
            }
        }
        .padding(.vertical, 10)
    }
}
