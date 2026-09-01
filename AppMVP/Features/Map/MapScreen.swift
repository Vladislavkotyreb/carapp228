import SwiftData
import SwiftUI

/// Раздел «Карта»: парковки, шиномонтаж и СТО вокруг, свои точки, избранное
/// и маршрут, который дальше подхватывает приложение Яндекс Карт.
///
/// Места показываются двумя способами — картой и списком, — и переключает их
/// системный сегментед-контрол. Так его и понимает HIG: выбор одной подачи из
/// нескольких взаимоисключающих, а не кнопка-режим и не переключатель.
///
/// Дизайна на раздел в Figma нет, поэтому подача собрана из того, что уже есть
/// в приложении: стекло, тёмная схема, те же кнопки и скругления. Список при
/// этом системный, со своими разделами и свайпами: подделывать `List` ради
/// единого вида значит потерять половину его поведения.
struct MapScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Place.createdAt) private var places: [Place]

    @StateObject private var controller = MapController()

    /// Карта или список. Состояние вью, а не контроллера: подача — дело
    /// экрана, карте и базе она безразлична.
    @State private var mode: MapMode = .map

    var body: some View {
        let phase = phase
        return Group {
            switch phase {
            case .noKey:
                missingKey
            case .live, .list, .listEmpty:
                content(phase: phase)
            }
        }
    }

    /// Что показывает раздел прямо сейчас. Считается типом, а не разбросано
    /// по условиям в вёрстке: список состояний раздела виден целиком.
    private var phase: MapPhase {
        MapPhase.of(mode: mode,
                    hasKey: MapKitKey.isConfigured,
                    hasPlaces: !sections.isEmpty)
    }

    private func content(phase: MapPhase) -> some View {
        // Под таббар и статус-бар уходит **только карта** — так стекло бара
        // работает как задумано. Всё остальное лежит рядом в `ZStack` и
        // безопасную зону соблюдает: иначе фильтры оказываются под островом.
        ZStack {
            // Карта живёт всё время, даже когда её не видно за списком.
            // Пересоздание `YMKMapView` при каждом переключении подачи заново
            // поднимало бы слой пользователя, слушателей и сессии — и теряло
            // бы место, на которое человек смотрел.
            YandexMapView(controller: controller)
                .ignoresSafeArea()
                .accessibilityHidden(mode == .list)

            switch mode {
            case .map:
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack { Spacer(minLength: 0); locateButton }
                    bottomCard
                }
                .padding(.bottom, legacyTabBarInset)
                .transition(.opacity)
            case .list:
                list(phase: phase)
                    .transition(.opacity)
            }
        }
            // Шапка объявлена врезкой в безопасную зону, а не слоем поверх:
            // тогда список сам получает отступ сверху и уезжает под неё при
            // прокрутке — ровно как содержимое под системной панелью.
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .animation(Motion.sheet, value: controller.selected)
            .animation(Motion.sheet, value: controller.route)
            .onAppear { controller.update(saved: places) }
            .onChange(of: places) { _, new in controller.update(saved: new) }
            .onDisappear { controller.detach() }
            // Добавили или убрали место — короткий отклик. Звезда без него
            // выглядит нажатой «в никуда»: строка не двигается, значок меняется
            // на 22 точках экрана.
            .sensoryFeedback(.impact(weight: .light), trigger: places.count)
            .sheet(item: $controller.draft) { draft in
                AddPlaceSheet(draft: draft) { title, kind in
                    modelContext.insert(Place(title: title, kind: kind,
                                              latitude: draft.latitude,
                                              longitude: draft.longitude))
                }
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
            }
            .alert("Не получилось",
                   isPresented: Binding(get: { controller.message != nil },
                                        set: { if !$0 { controller.message = nil } })) {
                Button("Понятно", role: .cancel) { controller.message = nil }
            } message: {
                Text(controller.message ?? "")
            }
    }

    /// Место под плавающим таббаром на iOS 17–25: там бар лежит поверх
    /// содержимого. На iOS 26 таббар системный и отступ резервирует сам —
    /// добавленный сверху, он стал бы вторым.
    private var legacyTabBarInset: CGFloat {
        if #available(iOS 26.0, *) { 0 } else { Figma.tabBarHeight + Figma.minBottomGap }
    }

    // MARK: - Шапка

    private var header: some View {
        VStack(spacing: 8) {
            modePicker
            filters
            if controller.keyRejected { keyBanner }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            // Над картой шапка висит без фона — там своё стекло у каждого
            // элемента. Над списком фон обязателен: под шапку уезжают строки,
            // и без подложки они читались бы сквозь неё.
            if mode == .list {
                Rectangle()
                    .fill(.bar)
                    .ignoresSafeArea(edges: .top)
            }
        }
    }

    private var modePicker: some View {
        Picker("Как показывать места", selection: $mode.animation(Motion.selection)) {
            ForEach(MapMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        // Во всю ширину сегментед-контрол читается как панель вкладок, а он
        // не она: HIG держит его узким и по центру.
        .frame(maxWidth: 280)
        // Своя подложка обязательна. Системный сегментед полупрозрачен —
        // он рассчитан лежать на фоне экрана, а не на карте, и без подложки
        // его подписи сталкивались с названиями улиц (снято на симуляторе).
        .padding(3)
        .liquidGlass(in: Self.pickerShape) { Self.pickerShape.fill(Material.regular) }
        // Схема — светлая, как у таббара и чипов: раздел идёт в тёмной ради
        // светлого статус-бара, но сами контролы в макете светлые.
        .environment(\.colorScheme, .light)
        .padding(.horizontal, 16)
        // HIG: смена сегмента — .selection, как у пикера и таббара.
        .sensoryFeedback(.selection, trigger: mode)
    }

    // MARK: - Фильтры

    private var filters: some View {
        HStack(spacing: 8) {
            ForEach(PlaceKind.allCases) { kind in
                chip(kind)
            }

            if controller.isSearching {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Figma.labelsPrimary)
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ kind: PlaceKind) -> some View {
        let isOn = controller.activeKinds.contains(kind)
        return Button {
            if isOn { controller.activeKinds.remove(kind) }
            else { controller.activeKinds.insert(kind) }
        } label: {
            Label(kind.plural, systemImage: kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isOn ? Color.white : Figma.labelsPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                // Чип рисуется на 35pt, но нажимается на 44: видимый размер
                // взят из макета, цель касания — из HIG.
                .frame(minHeight: 44)
                .liquidGlass(in: Capsule(), tint: isOn ? kind.tint : nil) {
                    Capsule().fill(isOn ? AnyShapeStyle(kind.tint)
                                        : AnyShapeStyle(Material.regular))
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.plural)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    /// Ключ отвергнут сервером. Показываем это прямо на карте: пустая сетка
    /// вместо тайлов выглядит как поломка приложения, хотя сломан не код.
    private var keyBanner: some View {
        Label("Яндекс не принял ключ MapKit — карта и поиск мест не работают",
              systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Figma.accentsRed.opacity(0.92),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
    }

    // MARK: - Список

    @ViewBuilder
    private func list(phase: MapPhase) -> some View {
        if phase == .listEmpty {
            emptyList
        } else {
            PlacesList(sections: sections,
                       onSelect: { pin in
                           controller.show(pin)
                           withAnimation(Motion.selection) { mode = .map }
                       },
                       onStar: toggleFavorite,
                       onDelete: delete,
                       onRefresh: { await controller.refresh() })
                .safeAreaPadding(.bottom, legacyTabBarInset)
        }
    }

    /// Пустой список. Системный `ContentUnavailableView`, а не свой текст
    /// посередине: у него и раскладка, и типографика, и поведение при крупном
    /// шрифте уже такие, какими их ждут от системы.
    private var emptyList: some View {
        ContentUnavailableView {
            Label("Мест пока нет", systemImage: "mappin.slash")
        } description: {
            Text("Рядом ничего не нашлось. Подвиньте карту или включите другие типы мест — звезда сохранит любое из них в избранное.")
        } actions: {
            Button("Искать заново") { controller.search() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Color(.systemGroupedBackground).ignoresSafeArea() }
    }

    /// Разделы списка. Пустые отсеиваются здесь же: пустой раздел — это
    /// заголовок без содержимого, и он читается как поломка.
    private var sections: [PlaceSection] {
        [PlaceSection(title: PlaceOrigin.favorite.section, rows: rows(saved: .favorite)),
         PlaceSection(title: PlaceOrigin.mine.section, rows: rows(saved: .mine)),
         PlaceSection(title: "Рядом", rows: nearbyRows)]
            .filter { !$0.rows.isEmpty }
    }

    private func rows(saved origin: PlaceOrigin) -> [PlaceRow] {
        sorted(places
            .filter { $0.origin == origin && controller.activeKinds.contains($0.kind) }
            .map { place in
                PlaceRow(pin: MapPin(place: place),
                         star: origin == .favorite ? .on : .hidden,
                         meters: meters(to: place.point))
            })
    }

    private var nearbyRows: [PlaceRow] {
        sorted(controller.nearby.map { pin in
            PlaceRow(pin: pin, star: .off, meters: meters(to: pin.point))
        })
    }

    /// Ближайшее сверху. Без геопозиции порядок остаётся исходным: у
    /// сохранённых это порядок добавления, у найденных — порядок выдачи
    /// Яндекса, и оба осмысленнее, чем сортировка по расстоянию, которого нет.
    private func sorted(_ rows: [PlaceRow]) -> [PlaceRow] {
        guard controller.here != nil else { return rows }
        return rows.sorted { ($0.meters ?? .infinity) < ($1.meters ?? .infinity) }
    }

    private func meters(to point: GeoPoint) -> Double? {
        guard let here = controller.here else { return nil }
        return MapGeo.meters(from: GeoPoint(latitude: here.latitude,
                                            longitude: here.longitude),
                             to: point)
    }

    // MARK: - Избранное

    /// Сохранённое место, которым является точка, — если она сохранена.
    ///
    /// У точки с карты есть идентификатор записи, у найденной — нет, и её
    /// приходится узнавать по названию и близости: из поиска она приходит
    /// заново и про базу ничего не знает.
    private func stored(_ pin: MapPin) -> Place? {
        if case .saved(let id) = pin.source {
            return places.first { $0.persistentModelID == id }
        }
        return places.first {
            MapGeo.isSamePlace($0.point, title: $0.title, pin.point, title: pin.title)
        }
    }

    /// Звезда: добавить место в избранное или убрать оттуда.
    ///
    /// «Убрать» — это удалить запись целиком, а не погасить у неё флаг: место
    /// никуда не делось, оно вернётся в раздел «Рядом» следующим же поиском.
    private func toggleFavorite(_ pin: MapPin) {
        if let saved = stored(pin) {
            modelContext.delete(saved)
        } else {
            modelContext.insert(Place(title: pin.title,
                                      kind: pin.kind,
                                      latitude: pin.latitude,
                                      longitude: pin.longitude,
                                      note: pin.subtitle,
                                      origin: .favorite))
        }
    }

    private func isFavorite(_ pin: MapPin) -> Bool { stored(pin)?.origin == .favorite }

    // MARK: - Кнопка «я здесь»

    private var locateButton: some View {
        Button(action: controller.centerOnMe) {
            Image(systemName: "location.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Figma.accentsBlue)
                .frame(width: 44, height: 44)
                .liquidGlass(in: Circle()) { Circle().fill(Material.regular) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.bottom, 12)
        .accessibilityLabel("Моё местоположение")
    }

    // MARK: - Карточка места

    @ViewBuilder
    private var bottomCard: some View {
        if let pin = controller.selected {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: pin.kind.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(pin.kind.tint)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pin.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(pin.subtitle ?? pin.kind.singular)
                            .font(.system(size: 13))
                            .foregroundStyle(Figma.vibrantSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    // Своя точка в избранное не добавляется: она и так своя.
                    // Пустая звезда рядом с ней предлагала бы действие,
                    // которого нет.
                    if stored(pin)?.origin != .mine { star(pin) }

                    Button { controller.selected = nil; controller.clearRoute() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Figma.vibrantSecondary)
                            // Кружок 28 — то, что видно; 44×44 — то, во что
                            // можно попасть пальцем. HIG требует второе, и
                            // отрицательный отступ не даёт цели раздвинуть
                            // раскладку карточки.
                            .frame(width: 28, height: 28)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(-8)
                    .accessibilityLabel("Закрыть")
                }

                if let route = controller.route {
                    // Маршрут построен: показываем, во что он обходится, и
                    // только потом предлагаем уйти в Яндекс Карты.
                    Label("\(route.time) · \(route.distance)", systemImage: "car.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)

                    GlassProminentButton(title: "Открыть в Яндекс Картах",
                                         lineHeight: 18,
                                         action: controller.openInYandexMaps)

                    // Высота 44: у текстовой кнопки цель касания иначе равна
                    // высоте строки, около 20pt.
                    Button("Убрать маршрут") { controller.clearRoute() }
                        .font(.system(size: 15))
                        .foregroundStyle(Figma.vibrantSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                } else {
                    GlassProminentButton(title: "Маршрут",
                                         lineHeight: 18,
                                         isBusy: controller.isRouting) {
                        controller.buildRoute(to: pin)
                    }
                }

                if stored(pin)?.origin == .mine {
                    Button("Удалить место", role: .destructive) { delete(pin) }
                        .font(.system(size: 15))
                        .foregroundStyle(Figma.accentsRed)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: Self.cardShape, tint: Figma.darkCard) {
                Self.cardShape.fill(Figma.darkCard)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func star(_ pin: MapPin) -> some View {
        let isOn = isFavorite(pin)
        return Button { toggleFavorite(pin) } label: {
            Image(systemName: isOn ? "star.fill" : "star")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOn ? Figma.accentsYellow : Figma.graysGray)
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                // Заполненная звезда вырастает из пустой, а не подменяется
                // кадром: замена значка — системная анимация, и она же читается
                // как «состояние изменилось», а не «появилось что-то другое».
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .padding(-8)
        .accessibilityLabel(isOn ? "Убрать из избранного" : "В избранное")
    }

    private static let cardShape = RoundedRectangle(cornerRadius: 28, style: .continuous)
    /// Скругление подложки сегментед-контрола: 9 у самого контрола плюс 3
    /// отступа вокруг него — чтобы кромка шла ровно вдоль его углов.
    private static let pickerShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    private func delete(_ pin: MapPin) {
        guard let place = stored(pin) else { return }
        if controller.selected == pin {
            controller.selected = nil
            controller.clearRoute()
        }
        modelContext.delete(place)
    }

    // MARK: - Без ключа

    /// Без ключа карта не рисуется вовсе. Показываем объяснение, а не пустой
    /// экран: иначе раздел выглядит сломанным, а не ненастроенным.
    private var missingKey: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Figma.vibrantSecondary)

            Text("Карта не настроена")
                .font(.system(size: 22, weight: .bold))
                .figmaLineHeight(28, fontSize: 22, weight: .bold)
                .foregroundStyle(Figma.labelsPrimary)

            Text("Добавьте ключ MapKit в MapKitKey.swift —\nбесплатно до 25 000 пользователей в месяц")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Figma.vibrantSecondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Figma.mainBackground)
    }
}

/// Форма добавления своего места. Обычный системный лист, а не своя шторка:
/// он сам накрывает таббар и сам отдаёт клавиатуре место.
private struct AddPlaceSheet: View {
    let draft: PlaceDraft
    let onSave: (String, PlaceKind) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind: PlaceKind = .parking
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Новое место")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Figma.labelsPrimary)

            TextField("Название", text: $title)
                .font(.system(size: 17))
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(Figma.fillsQuaternary, in: RoundedRectangle(cornerRadius: 14))
                .focused($titleFocused)
                .submitLabel(.done)

            Picker("Тип", selection: $kind) {
                ForEach(PlaceKind.allCases) { kind in
                    Text(kind.singular).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Spacer(minLength: 0)

            GlassProminentButton(title: "Добавить", lineHeight: 18) {
                let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
                onSave(name.isEmpty ? kind.singular : name, kind)
                dismiss()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Figma.backgroundsPrimary)
        .onAppear { titleFocused = true }
    }
}
