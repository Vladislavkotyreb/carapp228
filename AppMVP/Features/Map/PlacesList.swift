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
/// в списке «что и сколько до него». Подачу выбирает сегментед-контрол
/// наверху раздела.
///
/// Собран на системном `List`: разделы, свайпы и «потянуть, чтобы обновить»
/// у него уже правильные, и подделывать их своим `ScrollView` значит потерять
/// половину — начиная с того, что свайп по строке в самодельном списке никто
/// не напишет так же, как система.
struct PlacesList: View {
    let sections: [PlaceSection]
    let onSelect: (MapPin) -> Void
    let onStar: (MapPin) -> Void
    let onDelete: (MapPin) -> Void
    let onRefresh: () async -> Void

    var body: some View {
        List {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.rows) { row in
                        line(row)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await onRefresh() }
    }

    private func line(_ row: PlaceRow) -> some View {
        HStack(spacing: 12) {
            content(row)
                // Тап по строке и тап по звезде — разные действия, поэтому
                // они и разделены по площади: жест висит на содержимом, кнопка
                // стоит рядом. Вложенная в кнопку кнопка в списке срабатывает
                // вместе с внешней, и звезда открывала бы место на карте.
                .contentShape(Rectangle())
                .onTapGesture { onSelect(row.pin) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Показать на карте")

            star(row)
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
                .tint(Figma.accentsYellow)
            }
        }
    }

    private func content(_ row: PlaceRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.pin.kind.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(row.pin.kind.tint, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(row.pin.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(row.pin.subtitle ?? row.pin.kind.singular)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // Место при дележе ширины достаётся названию, а не расстоянию:
            // без приоритета `HStack` резал их поровну, и «Автосервис «Гараж»»
            // обрывался многоточием при пустой половине строки.
            .layoutPriority(1)

            Spacer(minLength: 8)

            if let meters = row.meters {
                // Моноширинные цифры: расстояния стоят колонкой, и обычные
                // цифры дёргали бы её при каждом обновлении позиции.
                Text(MapGeo.distanceLabel(meters: meters))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    // Сжиматься подпись не должна вовсе. Приоритет отдан
                    // названию, и без этого «710 м» разваливалось в колонку
                    // по одному символу — снято на симуляторе.
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func star(_ row: PlaceRow) -> some View {
        if row.star != .hidden {
            let isOn = row.star == .on
            Button {
                onStar(row.pin)
            } label: {
                Image(systemName: isOn ? "star.fill" : "star")
                    .font(.system(size: 17))
                    .foregroundStyle(isOn ? Figma.accentsYellow : Figma.graysGray)
                    // Значок 22, цель касания 44 — как требует HIG. Наружу
                    // строка от этого не растёт: её высота задана содержимым,
                    // которое выше.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    // Замена значка вместо появления нового: заполненная
                    // звезда вырастает из пустой, а не подменяется кадром.
                    .contentTransition(.symbolEffect(.replace))
            }
            // Обязателен: у кнопки со стилем по умолчанию внутри строки списка
            // область нажатия — вся строка.
            .buttonStyle(.borderless)
            .accessibilityLabel(isOn ? "Убрать из избранного" : "В избранное")
        }
    }
}
