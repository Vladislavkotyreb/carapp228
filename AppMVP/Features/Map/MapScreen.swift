import SwiftData
import SwiftUI

/// Раздел «Карта»: парковки, шиномонтаж и СТО вокруг, свои точки и маршрут,
/// который дальше подхватывает приложение Яндекс Карт.
///
/// Дизайна на раздел в Figma нет, поэтому подача собрана из того, что уже есть
/// в приложении: стекло, тёмная схема, те же кнопки и скругления.
struct MapScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Place.createdAt) private var places: [Place]

    @StateObject private var controller = MapController()

    var body: some View {
        Group {
            if MapKitKey.isConfigured {
                map
            } else {
                missingKey
            }
        }
    }

    private var map: some View {
        // Под таббар и статус-бар уходит **только карта** — так стекло бара
        // работает как задумано. Всё остальное лежит рядом в `ZStack` и
        // безопасную зону соблюдает: иначе фильтры оказываются под островом.
        ZStack {
            YandexMapView(controller: controller)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                filters
                if controller.keyRejected { keyBanner }
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack { Spacer(minLength: 0); locateButton }
                bottomCard
            }
        }
            .animation(Motion.sheet, value: controller.selected)
            .animation(Motion.sheet, value: controller.route)
            .onAppear { controller.update(saved: places) }
            .onChange(of: places) { _, new in controller.update(saved: new) }
            .onDisappear { controller.detach() }
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
        .padding(.top, 8)
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

                if pin.isSaved {
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

    private static let cardShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    private func delete(_ pin: MapPin) {
        guard case .saved(let id) = pin.source,
              let place = places.first(where: { $0.persistentModelID == id }) else { return }
        controller.selected = nil
        controller.clearRoute()
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
