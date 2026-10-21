import SwiftUI

/// Карточка места над его точкой на карте.
///
/// Открывается там, где нажали, а не шторкой снизу (образец пользователя,
/// 21.10.2026, — карта мест с карточками-выносками): вырастает из точки,
/// хвостиком на неё и показывает. Тап по карточке переворачивает её: на лице —
/// фото, название, адрес и оценка; на обороте — рубрики из списка, фото лентой
/// и действия. Тап по карте сворачивает карточку обратно в точку.
///
/// Заливка сплошная, а не стекло: карточка вырастает из точки и вращается в
/// пространстве, а `glassEffect` под такими преобразованиями рисуется
/// снимком и мигает.
struct PlaceCallout: View {
    let pin: MapPin
    let face: MapCardFace
    /// Ширина оборота: свободная ширина экрана. Лицо уже — оно подсказка, а не
    /// страница.
    let backWidth: CGFloat
    /// Подпись над фото: тип места, а у найденного кнопкой «Записаться» —
    /// «Ближайший сервис».
    let badge: String
    let isNearest: Bool
    /// «Автосервис · 350 м».
    let facts: String
    /// «350 м» — на лице рядом с оценкой.
    let distance: String?
    let star: PlaceStar
    let canDelete: Bool
    let onFlip: () -> Void
    let onClose: () -> Void
    let onRoute: () -> Void
    let onStar: () -> Void
    let onDelete: () -> Void

    @Environment(\.openURL) private var openURL

    /// Размеры карточки. Ширина лица и высота фото — с образца, пересчитанные
    /// на 393 точки; ритм — шаги по 4.
    enum Layout {
        static let frontWidth: CGFloat = 264
        static let heroHeight: CGFloat = 156
        static let radius: CGFloat = 26
        static let heroRadius: CGFloat = 18
        static let tailWidth: CGFloat = 24
        static let tailHeight: CGFloat = 10
        /// От центра значка точки до кончика хвостика: значки — 56 точек, а
        /// сама модель внутри начинается на восьмой.
        static let lift: CGFloat = 22
        /// Сколько значок занимает под точкой.
        static let below: CGFloat = 28
        static let badgeHeight: CGFloat = 32
        static let thumbWidth: CGFloat = 124
        static let thumbHeight: CGFloat = 88
        static let thumbRadius: CGFloat = 12
    }

    var body: some View {
        FlipCard(angle: face == .back ? 180 : 0) {
            front
        } back: {
            back
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, onClose)
        .accessibilityAction(named: face == .front ? "Подробнее" : "Свернуть", onFlip)
    }

    // MARK: - Лицо

    private var front: some View {
        VStack(alignment: .leading, spacing: 10) {
            hero

            VStack(alignment: .leading, spacing: 3) {
                if let address = pin.subtitle {
                    Text(address)
                        .font(.system(size: 13))
                        .foregroundStyle(Figma.labelsSecondary)
                        .lineLimit(1)
                }
                frontMeta
            }
            .padding(.horizontal, 6)
        }
        .padding(8)
        .padding(.bottom, 6)
        .frame(width: Layout.frontWidth, alignment: .leading)
        .modifier(CalloutSurface(onTap: onFlip))
        // Подпись типа сидит на верхней кромке, наполовину снаружи, как у
        // образца. Отступ сверху — чтобы её половина входила в размер
        // карточки: по нему камера решает, влезает ли карточка под поиск.
        .overlay(alignment: .top) { kindBadge.offset(y: -Layout.badgeHeight / 2) }
        .padding(.top, Layout.badgeHeight / 2)
        .accessibilityHint("Нажмите, чтобы открыть подробности")
    }

    /// Фото во всю ширину, а на нём — название. Нет фото — объёмный значок
    /// типа на подложке: карточка того же размера, и место узнаётся так же,
    /// как точка на карте.
    private var hero: some View {
        Color.clear
            .frame(height: Layout.heroHeight)
            .frame(maxWidth: .infinity)
            .background {
                if let url = pin.details.photoURL(.large) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .overlay {
                // Затемнение снизу — под белое название на любом фасаде.
                LinearGradient(colors: [.clear, .black.opacity(0.7)],
                               startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pin.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let line = heroLine {
                        Text(line)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: Layout.heroRadius, style: .continuous))
            // Фото шире рамки не должно ловить касания мимо неё.
            .contentShape(RoundedRectangle(cornerRadius: Layout.heroRadius, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Figma.fillsTertiary.opacity(0.24)
            kindIcon(size: 72)
                .offset(y: -16)
        }
    }

    /// Под названием — часы или первая рубрика: то, что отличает это место от
    /// соседнего того же типа.
    private var heroLine: String? {
        pin.details.hours ?? pin.details.categories.first
    }

    /// «★ 4,8 · 350 м».
    private var frontMeta: some View {
        HStack(spacing: 4) {
            if let rating = pin.details.ratingLabel {
                Image(systemName: "star.fill").font(.system(size: 10, weight: .semibold))
                Text(rating).monospacedDigit()
                if distance != nil { Text("·") }
            }
            if let distance { Text(distance) }
            if pin.details.ratingLabel == nil, distance == nil { Text(pin.kind.singular) }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Figma.labelsPrimary)
        .lineLimit(1)
    }

    private var kindBadge: some View {
        HStack(spacing: 4) {
            kindIcon(size: 26)
                .padding(.vertical, -4)
            Text(badge)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.black)
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: Layout.badgeHeight)
        .background(isNearest ? Figma.accentsYellow : Figma.labelsPrimary, in: Capsule())
        .compositingGroup()
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        .fixedSize()
        .allowsHitTesting(false)
    }

    // MARK: - Оборот

    private var back: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            let thumbs = pin.details.photoURLs(.medium)
            if !thumbs.isEmpty { photoStrip(thumbs) }

            if !pin.details.categories.isEmpty {
                PlaceTags(categories: pin.details.categories)
            }

            actions

            if canDelete {
                Button("Удалить место", role: .destructive, action: onDelete)
                    .font(.system(size: 15))
                    .foregroundStyle(Figma.accentsRed)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .padding(.vertical, -8)
            }
        }
        .padding(16)
        .frame(width: backWidth, alignment: .leading)
        .modifier(CalloutSurface(onTap: onFlip))
        .accessibilityHint("Нажмите, чтобы свернуть")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pin.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    if let rating = pin.details.ratingLabel {
                        Image(systemName: "star.fill").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Figma.labelsPrimary)
                        Text(rating).monospacedDigit().foregroundStyle(Figma.labelsPrimary)
                        Text("·")
                    }
                    Text(facts)
                        .foregroundStyle(isNearest ? Figma.accentsYellow : Figma.labelsSecondary)
                }
                .font(.system(size: 15))
                .foregroundStyle(Figma.labelsSecondary)
                .lineLimit(1)

                if let address = pin.subtitle {
                    Text(address)
                        .font(.system(size: 15))
                        .foregroundStyle(Figma.labelsSecondary)
                        .lineLimit(2)
                }

                if let hours = pin.details.hours {
                    Text(hours)
                        .font(.system(size: 15))
                        .foregroundStyle(Figma.labelsPrimary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            starButton
        }
    }

    /// Фото лентой, как у образца: кадр за кадром, следующий выглядывает.
    private func photoStrip(_ urls: [URL]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(urls, id: \.self) { url in
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Figma.fillsTertiary.opacity(0.24)
                        }
                    }
                    .frame(width: Layout.thumbWidth, height: Layout.thumbHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.thumbRadius, style: .continuous))
                }
            }
        }
        .frame(height: Layout.thumbHeight)
        // Лента выходит в край карточки: видно, что она листается.
        .padding(.horizontal, -16)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .accessibilityLabel("Фото места, \(urls.count)")
    }

    // MARK: Действия

    /// Плитки, как были в карточке внизу: маршрут — главная и единственная
    /// залитая. Плитки нет, если нет данных: пустая «Позвонить» обещала бы
    /// звонок в никуда.
    private var actions: some View {
        let booking = pin.contacts.filter { $0.channel != .website }
        let site = pin.contacts.first { $0.channel == .website }
        return HStack(spacing: 8) {
            MapActionTile(title: "Маршрут", symbol: "arrow.triangle.turn.up.right.diamond.fill",
                          prominent: true, action: onRoute)
                .accessibilityHint("Откроет маршрут в\u{00A0}Яндекс Картах")

            if let phone = pin.phone, let dial = PhoneFormat.dial(phone), let call = URL(string: dial) {
                MapActionTile(title: "Позвонить", symbol: "phone.fill") { openURL(call) }
                    .accessibilityValue(PhoneFormat.display(phone))
            }

            if booking.count == 1, let link = booking.first {
                MapActionTile(title: "Записаться", symbol: "calendar.badge.plus") { openURL(link.url) }
                    .accessibilityValue(link.channel.title)
            } else if booking.count > 1 {
                // Каналов бывает до пяти — в карточке над точкой списку
                // места нет, они раскрываются меню из плитки.
                Menu {
                    ForEach(booking, id: \.channel) { link in
                        Button { openURL(link.url) } label: {
                            Label(link.channel.title, systemImage: link.channel.symbol)
                        }
                    }
                } label: {
                    MapActionTile.label(title: "Записаться", symbol: "calendar.badge.plus")
                }
                .buttonStyle(.plain)
            }

            if let site {
                MapActionTile(title: "Сайт", symbol: "safari.fill") { openURL(site.url) }
            }
        }
    }

    @ViewBuilder
    private var starButton: some View {
        if star != .hidden {
            let isOn = star == .on
            Button(action: onStar) {
                Image(systemName: isOn ? "star.fill" : "star")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isOn ? Figma.labelsPrimary : Figma.graysGray)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .padding(-8)
            .accessibilityLabel(isOn ? "Убрать из избранного" : "В избранное")
        }
    }

    /// Значок вида места: объёмная модель — та же, что точка на карте.
    @ViewBuilder
    private func kindIcon(size: CGFloat) -> some View {
        if let model = pin.kind.model {
            Image(model).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: pin.kind.symbol).font(.system(size: size * 0.5, weight: .semibold))
        }
    }
}

// MARK: - Подложка с хвостиком

/// Подложка карточки: заливка, кромка, тень и хвостик на точку. Тап по
/// пустому месту карточки переворачивает её и до карты не доходит.
private struct CalloutSurface: ViewModifier {
    let onTap: () -> Void

    func body(content: Content) -> some View {
        let shape = CalloutShape()
        content
            .padding(.bottom, PlaceCallout.Layout.tailHeight)
            .background {
                shape.fill(Figma.darkCard)
                    .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
                    .overlay { shape.stroke(Figma.separatorsOnDark.opacity(0.7), lineWidth: 0.5) }
            }
            .contentShape(shape)
            .onTapGesture(perform: onTap)
    }
}

/// Скруглённый прямоугольник с хвостиком посередине снизу. Хвостик входит в
/// рамку: её низ — кончик хвостика, и именно эта точка садится над значком.
struct CalloutShape: Shape {
    var radius: CGFloat = PlaceCallout.Layout.radius
    var tailWidth: CGFloat = PlaceCallout.Layout.tailWidth
    var tailHeight: CGFloat = PlaceCallout.Layout.tailHeight

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY,
                          width: rect.width, height: rect.height - tailHeight)
        var path = Path(roundedRect: body, cornerRadius: radius, style: .continuous)
        // Хвостик — с мягкими плечами и скруглённым кончиком: острый треугольник
        // на скруглённой карточке выглядит приклеенным.
        let mid = rect.midX
        let half = tailWidth / 2
        var tail = Path()
        tail.move(to: CGPoint(x: mid - half - 6, y: body.maxY - 0.5))
        tail.addCurve(to: CGPoint(x: mid - 2.5, y: rect.maxY - 1.2),
                      control1: CGPoint(x: mid - half + 2, y: body.maxY),
                      control2: CGPoint(x: mid - 5, y: rect.maxY - 3.5))
        tail.addQuadCurve(to: CGPoint(x: mid + 2.5, y: rect.maxY - 1.2),
                          control: CGPoint(x: mid, y: rect.maxY + 0.6))
        tail.addCurve(to: CGPoint(x: mid + half + 6, y: body.maxY - 0.5),
                      control1: CGPoint(x: mid + 5, y: rect.maxY - 3.5),
                      control2: CGPoint(x: mid + half - 2, y: body.maxY))
        tail.closeSubpath()
        path.addPath(tail)
        return path
    }
}

// MARK: - Переворот

/// Переворот вокруг вертикальной оси, как у образца. Стороны разного размера,
/// поэтому в каждый момент на экране одна: подмена происходит на 90°, когда
/// карточка стоит ребром и скачка размера не видно.
///
/// `Animatable`, а не две вьюхи с прозрачностью: прозрачность плыла бы всю
/// анимацию, и посередине просвечивали бы обе стороны сразу.
private struct FlipCard<Front: View, Back: View>: View, Animatable {
    var angle: Double
    @ViewBuilder let front: Front
    @ViewBuilder let back: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        // Оборот доворачивается до нуля, а не стоит развёрнутым на 180° внутри
        // развёрнутого контейнера: в покое на нём ни одного преобразования, и
        // касания попадают туда, куда нарисовано.
        if angle < 90 {
            front.rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        } else {
            back.rotation3DEffect(.degrees(angle - 180), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        }
    }
}

// MARK: - Положение над точкой

/// Ставит карточку кончиком хвостика над точкой и держит её там, пока карта
/// едет. Камера меняется на каждом кадре, поэтому читает её только этот
/// модификатор: содержимое карточки на каждом кадре не пересобирается —
/// тот же приём, что `LevelReader` у живого шара.
struct PinAnchored: ViewModifier {
    @ObservedObject var projection: MapProjection
    let pin: MapPin?

    func body(content: Content) -> some View {
        let point = pin.flatMap { projection.point(latitude: $0.latitude, longitude: $0.longitude) }
        Color.clear
            .frame(width: 0, height: 0)
            .overlay(alignment: .bottom) { content.fixedSize() }
            .position(x: point?.x ?? 0, y: (point?.y ?? 0) - PlaceCallout.Layout.lift)
            .opacity(point == nil ? 0 : 1)
            .allowsHitTesting(point != nil)
    }
}

// MARK: - Плитка действия

/// Плитка действия карточки места и булавки, как в Apple Maps: значок над
/// подписью, первая — залитая.
struct MapActionTile: View {
    let title: String
    let symbol: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Self.label(title: title, symbol: symbol, prominent: prominent)
        }
        .buttonStyle(.plain)
    }

    /// Плитки и группа списка — 12, как у системных `.bordered` крупного
    /// размера и `insetGrouped`.
    static let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    static func label(title: String, symbol: String, prominent: Bool = false) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(height: 22)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(prominent ? Color.black : .white)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(prominent ? AnyShapeStyle(Figma.labelsPrimary)
                              : AnyShapeStyle(Figma.fillsTertiary),
                    in: shape)
        .contentShape(shape)
    }
}

extension ContactChannel {
    var symbol: String {
        switch self {
        case .booking: "calendar.badge.plus"
        case .telegram: "paperplane.fill"
        case .whatsapp: "message.fill"
        case .viber: "phone.bubble.left.fill"
        case .vk: "person.2.fill"
        case .website: "globe"
        }
    }
}
