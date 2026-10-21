import SwiftData
import SwiftUI

/// Раздел «Карта»: парковки, шиномонтаж и СТО вокруг, свои точки, избранное
/// и маршрут, который дальше подхватывает приложение Яндекс Карт.
///
/// Раскладка — по образцу Upside (выбор пользователя 03.10.2026, вместо
/// шторки мест): сверху поле поиска и ряд чипов — «Избранное» и типы мест,
/// справа внизу — «я здесь» и кнопка «Список». «Список» меняет
/// карту на список в той же вкладке; шторки, которая лежала под таббаром и
/// спорила с меню фильтров, больше нет.
///
/// Карточка появляется только по действию человека: нажал на точку —
/// карточка места над ней (`PlaceCallout`, 21.10.2026; раньше — внизу),
/// нажал на пустое место карты — булавка и «Новое место» внизу.
/// Карточку «ближайшее место», которая у Upside висит всегда, пользователь
/// снял в тот же день: она показывала место, о котором никто не спрашивал.
struct MapScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Place.createdAt) private var places: [Place]

    @StateObject private var controller = MapController()

    /// «Записаться» на главной: найти ближайший сервис и открыть его
    /// карточку. Флаг, а не вызов: вкладка может ещё не существовать в
    /// момент нажатия, и просьба должна дождаться её появления.
    @Binding var findsNearestService: Bool

    /// Что на экране: карта или список мест поверх неё.
    /// Состояние вью, а не контроллера: подача — дело экрана.
    @State private var mode: MapMode = .map
    /// Что набрано в поле поиска.
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    /// Какой стороной повёрнута карточка места. Новое место открывается лицом.
    @State private var face: MapCardFace = .front
    /// Свободная часть карты под карточку: рамка поиска с чипами и верх кнопок
    /// внизу, в координатах окна. Меняются только с раскладкой, не с кадром.
    @State private var chromeTop: CGRect = .zero
    @State private var chromeBottom: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Размеры и зазоры экрана. Высоты поля и чипов — из макета
    /// `46421:576`; остальное — HIG: поля экрана 16, цель касания 44, зазоры
    /// шагами по 4 — связанное ближе (поиск и его чипы — 12), несвязанное
    /// дальше (чипы и содержимое под ними — 16).
    private enum Layout {
        static let margin: CGFloat = 16
        static let chipHeight: CGFloat = 32
        static let searchHeight: CGFloat = 44
        /// Круглая кнопка и пилюля «Список» — 44, цель касания по HIG.
        static let control: CGFloat = 44
        /// Между плавающими элементами и от них до таббара.
        static let gap: CGFloat = 12
        /// От чипов до того, что под ними.
        static let section: CGFloat = 16
        /// Сколько списку оставить снизу под пилюлю «На карте».
        static let listTail: CGFloat = 72
        /// Зазор между карточкой над точкой и поиском или кнопками.
        static let calloutGap: CGFloat = 8
    }

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

    /// Разбито на слои, жизненный цикл и отклики: одной цепочкой компилятор
    /// не успевает вывести тип.
    private func content(phase: MapPhase) -> some View {
        feedback(lifecycle(layers(phase: phase)))
            .sheet(item: $controller.form) { draft in
                AddPlaceSheet { title, kind in
                    modelContext.insert(Place(title: title, kind: kind,
                                              latitude: draft.latitude,
                                              longitude: draft.longitude))
                    // Место сохранено — на его месте встаёт обычная точка.
                    controller.clearDraft()
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

    private func layers(phase: MapPhase) -> some View {
        ZStack(alignment: .bottom) {
            // Карта живёт всё время, даже когда её закрывает список.
            // Пересоздание `YMKMapView` заново поднимало бы слой
            // пользователя, слушателей и сессии — и теряло бы место, на
            // которое человек смотрел.
            YandexMapView(controller: controller)
                .ignoresSafeArea()
                .accessibilityHidden(mode == .list)

            // Карточка места — над точкой, в тех же координатах, что и карта:
            // слой во весь экран, касания мимо карточки уходят карте.
            calloutStage
                .ignoresSafeArea()

            if mode == .list {
                listPage(phase: phase)
                    .transition(.opacity)
            }

            bottomControls
        }
            // Поиск и чипы — общие для карты и списка: в списке они
            // отодвигают строки вниз, карта под ними остаётся во весь экран.
            .safeAreaInset(edge: .top, spacing: 0) {
                topBar
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { chromeTop = $0 }
            }
            .animation(Motion.sheet, value: controller.selected)
            .animation(Motion.sheet, value: controller.draft)
    }

    private func lifecycle(_ view: some View) -> some View {
        view
            .onAppear {
                controller.update(saved: places)
                controller.resume()
                consumeServiceRequest()
            }
            .onChange(of: findsNearestService) { _, wants in
                if wants { consumeServiceRequest() }
            }
            .onChange(of: places) { _, new in controller.update(saved: new) }
            // Поиск отвечает списком — поле в фокусе открывает список;
            // вернулись к карте — клавиатура уходит.
            .onChange(of: searchFocused) { _, focused in
                if focused { setMode(.list) }
            }
            .onChange(of: mode) { _, new in
                if new == .map { searchFocused = false }
            }
            // Другое место открывается лицом, без переворота на глазах.
            .onChange(of: controller.selected?.id) { _, _ in
                var plain = Transaction()
                plain.disablesAnimations = true
                withTransaction(plain) { face = .front }
            }
            .onDisappear { controller.detach() }
    }

    private func feedback(_ view: some View) -> some View {
        view
            // Добавили или убрали место — короткий отклик. Звезда без него
            // выглядит нажатой «в никуда»: строка не двигается, значок меняется
            // на 22 точках экрана.
            .sensoryFeedback(.impact(weight: .light), trigger: places.count)
            .sensoryFeedback(.selection, trigger: mode)
            .sensoryFeedback(.selection, trigger: face)
            // Карточка выросла из точки — лёгкий отклик, как у булавки.
            .sensoryFeedback(trigger: controller.selected?.id) { _, new in
                new == nil ? nil : .impact(weight: .light)
            }
            // Булавка воткнулась — отклик потяжелее; сняли — тишина.
            .sensoryFeedback(trigger: controller.draft) { _, new in
                new == nil ? nil : .impact(weight: .medium)
            }
    }

    private func consumeServiceRequest() {
        guard findsNearestService else { return }
        findsNearestService = false
        mode = .map
        controller.showNearestService()
    }

    /// Место под плавающим таббаром на iOS 17–25: там бар лежит поверх
    /// содержимого. На iOS 26 таббар системный и отступ резервирует сам —
    /// добавленный сверху, он стал бы вторым.
    private var legacyTabBarInset: CGFloat {
        if #available(iOS 26.0, *) { 0 } else { Figma.tabBarHeight + Figma.minBottomGap }
    }

    private func setMode(_ new: MapMode) {
        withAnimation(Motion.sheet) { mode = new }
    }

    // MARK: - Верх: поиск и чипы

    private var topBar: some View {
        VStack(spacing: Layout.gap) {
            if controller.keyRejected { keyBanner }

            searchField
                .padding(.horizontal, Layout.margin)

            chips
        }
        .padding(.top, 8)
        .padding(.bottom, Layout.section)
    }

    // MARK: - Список вместо карты

    /// Подписи «N мест рядом» над списком нет: пользователь снял её
    /// 03.10.2026 — число строк человек видит и так.
    private func listPage(phase: MapPhase) -> some View {
        Group {
            if phase == .listEmpty || sections.isEmpty {
                emptyList
            } else {
                PlacesList(sections: sections,
                           bottomInset: legacyTabBarInset + Layout.listTail,
                           onSelect: { pin in
                               controller.show(pin)
                               setMode(.map)
                           },
                           onStar: toggleFavorite,
                           onDelete: delete,
                           onRefresh: { await controller.refresh() })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Figma.sheetBackground.ignoresSafeArea())
    }

    // MARK: - Низ: кнопки и карточка

    /// По центру — переключатель «Список / На карте», справа на той же
    /// линии — «я здесь»; под ними карточка булавки или выбранного места,
    /// если они есть.
    private var bottomControls: some View {
        VStack(spacing: Layout.gap) {
            ZStack {
                // По центру, как «На карте» в Яндекс Картах (просьба
                // пользователя 03.10.2026): большой палец достаёт её с любой
                // руки, а справа она жалась к «я здесь». Над открытой
                // карточкой места или булавки её нет: человек занят одним
                // местом, и список в этот момент ни при чём.
                if !hasCard {
                    modeButton
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                if mode == .map {
                    locateButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, Layout.margin)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { chromeBottom = $0 }

            if mode == .map, let draft = controller.draft { draftCard(draft) }
        }
        .padding(.bottom, legacyTabBarInset + Layout.gap)
    }

    /// «Список» на карте и «На карте» в списке — одна кнопка на одном месте:
    /// куда ушёл, оттуда и возвращаешься.
    private var modeButton: some View {
        let toList = mode == .map
        return Button { setMode(toList ? .list : .map) } label: {
            HStack(spacing: 8) {
                Image(systemName: toList ? "list.bullet" : "map.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text(toList ? "Список" : "На\u{00A0}карте")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundStyle(Figma.labelsPrimary)
            .padding(.horizontal, 18)
            .frame(height: Layout.control)
            .liquidGlass(in: Capsule()) { Capsule().fill(Material.regular) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Открыта ли на карте карточка — места или булавки.
    private var hasCard: Bool {
        mode == .map && (controller.selected != nil || controller.draft != nil)
    }

    // MARK: - Булавка

    /// Карточка булавки: место ещё не добавлено, человек только показал, где
    /// оно. Главное действие — добавить; маршрут — потому что отметить точку
    /// и поехать к ней просят не реже.
    private func draftCard(_ draft: PlaceDraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Новое место")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)

                    Text(draftFacts(draft))
                        .font(.system(size: 15))
                        .foregroundStyle(Figma.labelsSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                closeButton { controller.clearDraft() }
            }

            HStack(spacing: 8) {
                MapActionTile(title: "Добавить место", symbol: "plus", prominent: true) {
                    controller.nameDraft()
                }
                MapActionTile(title: "Маршрут", symbol: "arrow.triangle.turn.up.right.diamond.fill") {
                    controller.openInYandexMaps(latitude: draft.latitude,
                                                longitude: draft.longitude)
                }
                .accessibilityHint("Откроет маршрут в\u{00A0}Яндекс Картах")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: Self.cardShape, tint: Figma.darkCard) {
            Self.cardShape.fill(Figma.darkCard)
        }
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func draftFacts(_ draft: PlaceDraft) -> String {
        guard let meters = meters(to: draft.point) else { return "Булавка на\u{00A0}карте" }
        return "Булавка · \(MapGeo.distanceLabel(meters: meters)) от\u{00A0}вас"
    }

    // MARK: - Поиск

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Figma.graysGray)

            TextField("СТО, шиномонтаж или адрес", text: $query)
                .font(.system(size: 16))
                .foregroundStyle(Figma.labelsPrimary)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                // Пока печатают — список отбирается на месте; «Найти» отдаёт
                // запрос Яндексу: услугу или адрес по названиям не найти.
                .onSubmit {
                    controller.search(text: query)
                    searchFocused = false
                }

            // Ход поиска виден здесь — другой подписи у экрана нет.
            if controller.isSearching || controller.isFindingService, query.isEmpty {
                ProgressView().controlSize(.small).tint(Figma.graysGray)
            }

            if !query.isEmpty {
                Button {
                    query = ""
                    if controller.textQuery != nil { controller.search(text: "") }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Figma.graysGray)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, -12)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Layout.searchHeight)
        // Стекло, а не заливка: поле лежит на карте. Одна подложка для карты
        // и списка — смена модификатора по режиму пересоздала бы поле и
        // сбросила фокус ровно в момент, когда его дали.
        .liquidGlass(in: Capsule()) { Capsule().fill(Material.regular) }
    }

    // MARK: - Фильтры

    /// Чипы типов — без цвета категории: выбранный белый, остальные на
    /// стекле; тип различает значок (решение пользователя 03.10.2026).
    /// Строка листается вбок — новые типы не упрутся в край экрана.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // «Избранное» — чип в общем ряду (просьба пользователя
                // 03.10.2026): оставляет на карте и в списке только своё —
                // избранное и поставленные точки.
                chip("Избранное", symbol: "star.fill", model: "MapIconStar", isOn: controller.savedOnly) {
                    withAnimation(Motion.sheet) { controller.savedOnly.toggle() }
                }
                ForEach(Self.filterOrder) { kind in
                    chip(kind.plural, symbol: kind.symbol, model: kind.model,
                         isOn: controller.activeKinds.contains(kind)) { toggle(kind) }
                }
            }
            .padding(.horizontal, Layout.margin)
        }
    }

    /// Порядок типов в чипах — как в макете: СТО первым, за ним приложение
    /// и открывают.
    private static let filterOrder: [PlaceKind] = [.service, .tyre, .parking]

    private func toggle(_ kind: PlaceKind) {
        if controller.activeKinds.contains(kind) { controller.activeKinds.remove(kind) }
        else { controller.activeKinds.insert(kind) }
    }

    private func chip(_ title: String, symbol: String, model: String? = nil, isOn: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Значок полужирный, подпись обычная — как в макете.
            HStack(spacing: 6) {
                // Объёмная модель, где она есть (опыт 08.10.2026: «3D во
                // всём интерфейсе»); иначе прежний значок.
                if let model {
                    Image(model).resizable().scaledToFit()
                        .frame(width: 24, height: 24)
                        .padding(.vertical, -4)
                } else {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(.system(size: 14))
            }
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isOn ? Color.black : Figma.labelsPrimary)
                .padding(.leading, 10)
                .padding(.trailing, 14)
                .frame(height: Layout.chipHeight)
                // Выбранный — сплошной белый, без стекла: подкрашенное
                // стекло пропускало карту, и «включено» читалось как
                // «полупрозрачно».
                .liquidGlass(in: Capsule(), kind: isOn ? .painted : .regular) {
                    Capsule().fill(isOn ? AnyShapeStyle(Figma.labelsPrimary)
                                        : AnyShapeStyle(Material.regular))
                }
                // Чип рисуется на 32, но нажимается на 44: видимый размер
                // взят из макета, цель касания — из HIG.
                .contentShape(Capsule().inset(by: -6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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

    /// Пусто в списке: коротко, почему, и что с этим сделать.
    private var emptyList: some View {
        VStack(spacing: 10) {
            Text(controller.savedOnly
                 ? "Отметьте место звездой или поставьте булавку"
                 : "Подвиньте карту или включите другие типы мест")
                .font(.system(size: 15))
                .foregroundStyle(Figma.graysGray)
                .multilineTextAlignment(.center)

            if !controller.savedOnly {
                Button("Искать заново") { controller.search() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Figma.labelsPrimary)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Что в списке. Раздел один и без заголовка, как в макете `46421:576`:
    /// свои места стоят в общем ряду по расстоянию и отличаются звездой, а не
    /// отдельным блоком наверху, — далёкое избранное иначе оттесняло бы
    /// ближайшее. Только свои оставляет чип «Избранное».
    private var sections: [PlaceSection] {
        let saved = rows(saved: .favorite) + rows(saved: .mine)
        let rows = sorted(controller.savedOnly ? saved : saved + nearbyRows)
        // Пустой раздел не отдаём: по пустому списку экран показывает
        // объяснение вместо строк.
        return rows.isEmpty ? [] : [PlaceSection(title: "Рядом", rows: rows)]
    }

    /// Подходит ли место под набранное в поиске.
    private func matchesQuery(_ pin: MapPin) -> Bool {
        MapGeo.matches(query: query, title: pin.title, subtitle: pin.subtitle)
    }

    private func rows(saved origin: PlaceOrigin) -> [PlaceRow] {
        sorted(places
            .filter { $0.origin == origin && controller.activeKinds.contains($0.kind) }
            .map { place -> MapPin in
                var pin = MapPin(place: place)
                // Фото и рейтинг в базе не лежат. Если поиск нашёл это же
                // место рядом — берём их оттуда, иначе избранное в списке
                // выглядело бы беднее только что найденного.
                if let twin = controller.found.first(where: {
                    MapGeo.isSamePlace(place.point, title: place.title, $0.point, title: $0.title)
                }) {
                    pin.details = twin.details
                }
                return pin
            }
            .filter(matchesQuery)
            .map { pin in
                PlaceRow(pin: pin,
                         star: origin == .favorite ? .on : .hidden,
                         meters: meters(to: pin.point))
            })
    }

    private var nearbyRows: [PlaceRow] {
        // Запрос уже отдан Яндексу — найденное показываем как есть: услугу
        // («замена масла») в названии места искать бессмысленно. Пока текст
        // только печатают — отбираем на месте.
        let submitted = controller.textQuery ?? ""
        let typing = query.trimmingCharacters(in: .whitespacesAndNewlines) != submitted
        return sorted(controller.nearby
            .filter { !typing || matchesQuery($0) }
            .map { pin in
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
                                      phone: pin.phone,
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
        .accessibilityLabel("Моё местоположение")
    }

    // MARK: - Карточка места над точкой

    /// Слой карточки: во весь экран, в координатах карты. Карточка стоит
    /// хвостиком над точкой (`PinAnchored`) и вырастает из неё — масштаб от
    /// кончика хвостика, с перелётом, как у образца; сворачивается туда же.
    private var calloutStage: some View {
        Group {
            if mode == .map, let pin = controller.selected {
                callout(pin)
                    .id(pin.id)
                    .transition(reduceMotion
                                ? .opacity
                                : .scale(scale: 0.2, anchor: .bottom).combined(with: .opacity))
            }
        }
        .modifier(PinAnchored(projection: controller.projection, pin: controller.anchorPin))
        .animation(reduceMotion ? Motion.fade : Motion.callout, value: controller.selected?.id)
        // При «Уменьшении движения» карточка не вращается — сторона просто
        // сменяется.
        .animation(reduceMotion ? nil : Motion.flip, value: face)
    }

    private func callout(_ pin: MapPin) -> some View {
        let room = calloutRoom
        let isMine = stored(pin)?.origin == .mine
        let isNearest = pin.id == controller.nearestServiceID
        return PlaceCallout(
            pin: pin,
            face: face,
            backWidth: max(PlaceCallout.Layout.frontWidth, CGFloat(room.trailing - room.leading)),
            badge: isNearest ? "Ближайший сервис" : pin.kind.singular,
            isNearest: isNearest,
            facts: facts(pin),
            distance: meters(to: pin.point).map { MapGeo.distanceLabel(meters: $0) },
            // Своя точка в избранное не добавляется: она и так своя.
            star: isMine ? .hidden : (isFavorite(pin) ? .on : .off),
            canDelete: isMine,
            onFlip: { face = face.flipped },
            onClose: { controller.selected = nil },
            onRoute: { controller.openInYandexMaps(to: pin) },
            onStar: { toggleFavorite(pin) },
            onDelete: { delete(pin) })
            // Размер — раскладочный, без масштаба появления: камера с первого
            // кадра знает, сколько места нужно карточке.
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                guard room.trailing > room.leading else { return }
                controller.reveal(card: size, room: room)
            }
    }

    /// Свободная часть карты: под поиском с чипами, над кнопками, с полями
    /// экрана по бокам. В координатах окна — точку в них переводит контроллер.
    /// Рамку самой карты отсюда не мерить: у вьюхи с `ignoresSafeArea` замер
    /// отдаёт рамку без вылета под края (проверено 21.10.2026 — 143 точки
    /// вместо нуля).
    private var calloutRoom: CalloutRoom {
        CalloutRoom(top: Double(chromeTop.maxY + Layout.calloutGap),
                    bottom: Double(chromeBottom - Layout.calloutGap),
                    leading: Double(chromeTop.minX + Layout.margin),
                    trailing: Double(chromeTop.maxX - Layout.margin))
    }

    private func closeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Figma.graysGray2)
                // Кружок 30 — системный крестик шторки; 44×44 — цель
                // касания по HIG. Отрицательный отступ не даёт ей
                // раздвинуть шапку.
                .frame(width: 30, height: 30)
                .background(Figma.fillsTertiary, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-7)
        .accessibilityLabel("Закрыть")
    }

    /// «Автосервис · 350 м», а у найденного кнопкой «Записаться» — «Ближайший
    /// сервис · 350 м»: человек должен видеть, почему открыт именно этот.
    private func facts(_ pin: MapPin) -> String {
        let head = pin.id == controller.nearestServiceID ? "Ближайший сервис" : pin.kind.singular
        guard let meters = meters(to: pin.point) else { return head }
        return "\(head) · \(MapGeo.distanceLabel(meters: meters))"
    }

    private static let cardShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    private func delete(_ pin: MapPin) {
        guard let place = stored(pin) else { return }
        if controller.selected == pin {
            controller.selected = nil
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
        .background(Figma.backgroundsPrimary)
    }
}

/// Форма добавления своего места. Обычный системный лист, а не своя шторка:
/// он сам накрывает таббар и сам отдаёт клавиатуре место.
private struct AddPlaceSheet: View {
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
        // Системный лист в тёмной схеме — приподнятая поверхность, не чистый
        // чёрный: фон тот же, что у остальных шторок.
        .background(Figma.sheetBackground)
        .onAppear { titleFocused = true }
    }
}
