import SwiftUI

enum OnboardingFeature { case plate, sound, trips }

/// Все иллюстрации занимают одну область; внутренние пропорции не зависят от страницы.
struct OnboardingVisual: View {
    let feature: OnboardingFeature
    var isActive = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private static let car: UIImage? = {
        guard let url = Bundle.main.url(forResource: "toyota-camry-70", withExtension: "heic", subdirectory: "CarCatalog") else { return nil }
        return UIImage(contentsOfFile: url.path)?.preparingForDisplay()
    }()

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 310, geometry.size.height / 280)
            Group {
                switch feature {
                case .plate: car
                case .sound: wave
                case .trips: route
                }
            }
            .frame(width: 310, height: 280)
            .scaleEffect(scale)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    private var car: some View {
        VStack(spacing: 12) {
            Group {
                if let image = Self.car { Image(uiImage: image).resizable() }
                else { Image("CarPhoto").resizable() }
            }
            .scaledToFit()
            .frame(width: 310, height: 206)
            HStack(spacing: 12) {
                Text("А 777 АА")
                    .font(.system(size: 25, weight: .semibold, design: .monospaced))
                Rectangle().fill(.black.opacity(0.18)).frame(width: 1, height: 28)
                VStack(spacing: 1) {
                    Text("777").font(.system(size: 17, weight: .semibold, design: .monospaced))
                    Text("RUS").font(.system(size: 8, weight: .semibold))
                }
            }
            .foregroundStyle(.black)
            .frame(width: 236, height: 50)
            .background(Color(white: 0.94), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.5), lineWidth: 1))
        }
    }

    private var wave: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isActive || reduceMotion || scenePhase != .active)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let count = 45
                let spacing = size.width / CGFloat(count)
                for index in 0..<count {
                    let distance = abs(Double(index - count / 2)) / Double(count / 2)
                    let envelope = pow(cos(distance * .pi / 2), 1.8)
                    let pulse = 0.62 + 0.38 * sin(distance * 15 - time * 2.4)
                    let height = 5 + CGFloat(envelope * pulse) * 190
                    let rect = CGRect(x: (CGFloat(index) + 0.5) * spacing - 1.75,
                                      y: (size.height - height) / 2, width: 3.5, height: height)
                    canvas.fill(Path(roundedRect: rect, cornerRadius: 1.75),
                                with: .color(Color(red: 1, green: 0.43, blue: 0.34)))
                }
            }
        }
    }

    private var route: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28).fill(Color(red: 0.11, green: 0.15, blue: 0.12))
            Canvas { canvas, _ in
                // Улицы и маршрут используют одну геометрию: линия проходит по дорогам.
                var streets = Path()
                for x in [CGFloat(48), 110, 180, 252] {
                    streets.move(to: CGPoint(x: x, y: 0))
                    streets.addLine(to: CGPoint(x: x, y: 202))
                }
                for y in [CGFloat(40), 96, 158] {
                    streets.move(to: CGPoint(x: 0, y: y))
                    streets.addLine(to: CGPoint(x: 300, y: y))
                }
                canvas.stroke(streets, with: .color(.white.opacity(0.06)), lineWidth: 12)
                var path = Path()
                path.move(to: CGPoint(x: 48, y: 158))
                path.addLine(to: CGPoint(x: 96, y: 158))
                path.addQuadCurve(to: CGPoint(x: 110, y: 144), control: CGPoint(x: 110, y: 158))
                path.addLine(to: CGPoint(x: 110, y: 110))
                path.addQuadCurve(to: CGPoint(x: 124, y: 96), control: CGPoint(x: 110, y: 96))
                path.addLine(to: CGPoint(x: 238, y: 96))
                path.addQuadCurve(to: CGPoint(x: 252, y: 82), control: CGPoint(x: 252, y: 96))
                path.addLine(to: CGPoint(x: 252, y: 40))
                canvas.stroke(path, with: .color(.orange.opacity(0.15)), style: StrokeStyle(lineWidth: 13, lineCap: .round))
                canvas.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            Circle().fill(.white).frame(width: 14, height: 14)
                .overlay(Circle().fill(.orange).padding(4))
                .position(x: 48, y: 158)
            Image(systemName: "location.north.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 38, height: 38)
                .background(.white, in: Circle())
                .position(x: 252, y: 40)
            HStack(spacing: 0) {
                Label("12,4\u{00A0}км", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                Spacer()
                Text("24\u{00A0}мин").foregroundStyle(.secondary)
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 20)
            .frame(width: 300, height: 58)
            .background(.black.opacity(0.18))
            .position(x: 150, y: 231)
        }
        .frame(width: 300, height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}
