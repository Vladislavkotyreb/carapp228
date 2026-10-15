import SwiftUI

/// Что делает звезда в строке списка.
///
/// Три состояния, а не булево: у своей точки звезды нет вовсе — она не
/// «не в избранном», она другого рода, и пустая звезда рядом с ней предлагала
/// бы действие, которого нет.
enum PlaceStar {
    /// Место в избранном — звезда закрашена, тап убирает.
    case on
    /// Найденное место — звезда пустая, тап добавляет.
    case off
    /// Своя точка — звезды нет, место удаляют свайпом.
    case hidden
}

/// Строка списка мест.
struct PlaceRow: Identifiable {
    let pin: MapPin
    let star: PlaceStar
    /// Расстояние от пользователя, метры. `nil` — позиции ещё нет.
    let meters: Double?

    var id: String { pin.id }
}

/// Раздел списка. Пустые разделы сюда не доезжают — их отсеивает экран.
struct PlaceSection: Identifiable {
    let title: String
    let rows: [PlaceRow]

    var id: String { title }
}

/// Список мест: избранное, свои точки и найденное рядом.
///
/// Вторая подача тех же данных, что и карта, — на карте место видно «где»,
/// в списке «что это и сколько до него». Открывается кнопкой «Список»
/// (`MapScreen`).
///
/// Место — карточка, как в списке Яндекс Карт (образец пользователя,
/// 03.10.2026): фото во всю ширину, название и рейтинг, часы и расстояние,
/// адрес, рубрики. Тап открывает место на карте. Быстрых действий в списке
/// нет: раньше они стояли у первой строки и спорили с тем же тапом —
/// «Маршрут» и «Позвонить» живут в карточке места на карте.
///
/// Собран на системном `List`: свайпы и «потянуть, чтобы обновить» у него
/// уже правильные, и подделывать их своим `ScrollView` значит потерять
/// половину — начиная с того, что свайп по строке в самодельном списке никто
/// не напишет так же, как система. Фон и подложки строк прозрачные.
struct PlacesList: View {
    let sections: [PlaceSection]
    /// Место под плавающим таббаром и кнопкой «На карте»: последняя карточка
    /// не должна под ними оставаться.
    var bottomInset: CGFloat = 0
    let onSelect: (MapPin) -> Void
    let onStar: (MapPin) -> Void
    let onDelete: (MapPin) -> Void
    let onRefresh: () async -> Void

    /// Звонок уходит системе через окружение — в списке по той же причине,
    /// что и на карточке карты: вью не знает про UIKit.
    @Environment(\.openURL) private var openURL

    /// Размеры карточки. Ритм — шаги по 4: 4 внутри текстового блока, 12
    /// между фото и текстом, 24 между карточками (HIG: связанное ближе,
    /// несвязанное дальше).
    private enum Card {
        static let photoRadius: CGFloat = 20
        /// Стороны фото — 2 : 1, как отдаёт хранилище Яндекса.
        static let photoRatio: CGFloat = 2
        static let textGap: CGFloat = 4
        static let photoGap: CGFloat = 12
        static let between: CGFloat = 24
        static let tagHeight: CGFloat = 24
        static let icon: CGFloat = 44
    }

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        card(row)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16,
                                                      bottom: Card.between, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    // Один раздел заголовка не просит: подпись над списком
                    // уже сказала, что в нём.
                    if sections.count > 1 {
                        Text(section.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Figma.graysGray)
                            .textCase(nil)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 2, trailing: 16))
                    }
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        // Системный заголовок раздела в `.plain` держит минимум высоты и
        // зазор сверху — между подписью и первой карточкой выходила дыра.
        .environment(\.defaultMinListHeaderHeight, 0)
        .listSectionSpacing(0)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, bottomInset, for: .scrollContent)
        .refreshable { await onRefresh() }
    }

    // MARK: - Карточка

    private func card(_ row: PlaceRow) -> some View {
        let photo = row.pin.details.photoURL(.large)
        return VStack(alignment: .leading, spacing: Card.photoGap) {
            if let photo {
                self.photo(photo, row: row)
            }

            HStack(alignment: .top, spacing: 12) {
                // Без фото место узнают по значку типа — как точку на карте.
                if photo == nil {
                    kindIcon(row.pin, size: 17, model: 34)
                        .foregroundStyle(Figma.labelsPrimary)
                        .frame(width: Card.icon, height: Card.icon)
                        .background(Figma.fillsTertiary, in: Circle())
                }

                text(row)

                // На фото звезда лежит поверх него; без фото — в строке.
                if photo == nil { star(row, onPhoto: false) }
            }
        }
        // Тап по карточке и тап по звезде — разные действия, поэтому жест
        // висит на содержимом, а звезда — отдельная кнопка поверх. Вложенная
        // в кнопку кнопка в списке срабатывает вместе с внешней, и звезда
        // открывала бы место на карте.
        .contentShape(Rectangle())
        .onTapGesture { onSelect(row.pin) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Показать на карте")
        // Звонок вынесен на левый край: правый занят удалением, и класть
        // звонок рядом с разрушающим действием значит однажды удалить место
        // вместо вызова.
        .swipeActions(edge: .leading) {
            if let url = callURL(row.pin) {
                Button { openURL(url) } label: {
                    Label("Позвонить", systemImage: "phone.fill")
                }
                .tint(Figma.accentsGreen)
            }
        }
        .swipeActions(edge: .trailing) {
            switch row.star {
            case .hidden:
                // Метки, а не голый текст: система сама решит, что показать
                // при узкой строке, — значок или подпись.
                Button(role: .destructive) { onDelete(row.pin) } label: {
                    Label("Удалить", systemImage: "trash")
                }
            case .on:
                Button { onStar(row.pin) } label: {
                    Label("Убрать", systemImage: "star.slash")
                }
                .tint(Figma.graysGray)
            case .off:
                Button { onStar(row.pin) } label: {
                    Label("В избранное", systemImage: "star")
                }
                .tint(Figma.graysGray)
            }
        }
    }

    private func photo(_ url: URL, row: PlaceRow) -> some View {
        // Рамка задана заранее, а не картинкой: иначе карточка прыгала бы
        // по высоте, когда фото догружается, и список дёргался под пальцем.
        Color.clear
            .aspectRatio(Card.photoRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        // Пока фото едет — и если не доехало: подложка со
                        // значком типа, а не пустой серый прямоугольник.
                        ZStack {
                            Figma.fillsTertiary.opacity(0.24)
                            kindIcon(row.pin, size: 32, model: 72)
                                .foregroundStyle(Figma.labelsTertiary)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Card.photoRadius, style: .continuous))
            .overlay(alignment: .topTrailing) { star(row, onPhoto: true) }
            .accessibilityHidden(true)
    }

    /// Значок вида места: объёмная модель, где она есть, иначе SF Symbol.
    @ViewBuilder
    private func kindIcon(_ pin: MapPin, size: CGFloat, model side: CGFloat) -> some View {
        if let model = pin.kind.model {
            Image(model).resizable().scaledToFit().frame(width: side, height: side)
        } else {
            Image(systemName: pin.kind.symbol).font(.system(size: size, weight: .semibold))
        }
    }

    private func text(_ row: PlaceRow) -> some View {
        let details = row.pin.details
        return VStack(alignment: .leading, spacing: Card.textGap) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.pin.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Figma.labelsPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let rating = details.ratingLabel {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").font(.system(size: 11, weight: .semibold))
                        Text(rating).font(.system(size: 15, weight: .medium)).monospacedDigit()
                    }
                    .foregroundStyle(Figma.labelsPrimary)
                    // Сжиматься оценка не должна: место при дележе ширины
                    // достаётся названию.
                    .fixedSize()
                    .accessibilityLabel("Оценка \(rating)")
                }
            }

            if let facts = facts(row) {
                Text(facts)
                    .font(.system(size: 15))
                    .foregroundStyle(Figma.labelsPrimary)
                    .lineLimit(1)
            }

            Text(row.pin.subtitle ?? row.pin.kind.singular)
                .font(.system(size: 15))
                .foregroundStyle(Figma.graysGray)
                .lineLimit(2)

            if !details.categories.isEmpty {
                tags(details.categories)
                    .padding(.top, Card.textGap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// «До 20:00 · 390 м»: открыто ли и далеко ли — два вопроса, с которыми
    /// выбирают, куда ехать.
    private func facts(_ row: PlaceRow) -> String? {
        let distance = row.meters.map { MapGeo.distanceLabel(meters: $0) }
        let parts = [row.pin.details.hours, distance].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Рубрики Яндекса — серыми метками в одну строку; что не влезло,
    /// листается вбок, как у образца.
    private func tags(_ categories: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(categories, id: \.self) { category in
                    Text(category)
                        .font(.system(size: 13))
                        .foregroundStyle(Figma.labelsSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: Card.tagHeight)
                        .background(Figma.fillsTertiary.opacity(0.24),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Ссылка для звонка или `nil`: у своих точек телефона нет вовсе,
    /// а у найденных он приходит не всегда.
    private func callURL(_ pin: MapPin) -> URL? {
        guard let phone = pin.phone, let dial = PhoneFormat.dial(phone) else { return nil }
        return URL(string: dial)
    }

    @ViewBuilder
    private func star(_ row: PlaceRow, onPhoto: Bool) -> some View {
        if row.star != .hidden {
            let isOn = row.star == .on
            Button {
                onStar(row.pin)
            } label: {
                Image(systemName: isOn ? "star.fill" : "star")
                    .font(.system(size: onPhoto ? 20 : 17, weight: .semibold))
                    // Белая, а не жёлтая: цветных меток в разделе нет. На фото
                    // — с тенью: фасад бывает и белым.
                    .foregroundStyle(onPhoto || isOn ? Figma.labelsPrimary : Figma.graysGray)
                    .shadow(color: .black.opacity(onPhoto ? 0.45 : 0), radius: 4, y: 1)
                    // Цель касания 44 — как требует HIG.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    // Замена значка вместо появления нового: заполненная
                    // звезда вырастает из пустой, а не подменяется кадром.
                    .contentTransition(.symbolEffect(.replace))
            }
            // Обязателен: у кнопки со стилем по умолчанию внутри строки списка
            // область нажатия — вся строка.
            .buttonStyle(.borderless)
            .padding(onPhoto ? 4 : 0)
            .accessibilityLabel(isOn ? "Убрать из избранного" : "В избранное")
        }
    }
}
