import SwiftData
import SwiftUI

/// «Ещё» → «Поездки»: история карточками, как в Делимобиле (образец
/// пользователя, 08.10.2026). У каждой поездки карта с путём, дата и машина,
/// справа расстояние; тап открывает экран поездки, там же лишнюю удаляют.
///
/// На своём экране список целиком: прежние шесть последних поездок были
/// ограничением ленты «Ещё», где история делила место с настройкой.
struct TripsPage: View {
    @Query(sort: \Trip.endedAt, order: .reverse) private var trips: [Trip]
    @Environment(\.modelContext) private var modelContext

    /// Поездка, открытая экраном с картой.
    @State private var opened: TripDetails?

    /// Скольким поездкам за заход спрашивать адреса: геокодер — сеть, а
    /// старые поездки человек открывает редко.
    private static let geocoded = 20

    var body: some View {
        MorePage(title: "Поездки") {
            if trips.isEmpty {
                Text("Пока нет")
                    .font(.system(size: 15))
                    .foregroundStyle(Figma.graysGray)
                    .padding(.horizontal, 16)
            } else {
                // Ленивая стопка: кадр карты рисуется, когда карточка подошла
                // к экрану, а не для всех разом.
                LazyVStack(spacing: 12) {
                    ForEach(trips) { trip in
                        let details = TripDetails(trip)
                        Button { opened = details } label: { TripCard(trip: details) }
                            .buttonStyle(CardPressStyle())
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Открыть поездку")
                    }
                }
            }
        }
        .sheet(item: $opened) { trip in
            TripSheet(trip: trip, onDelete: { delete(trip) }) { opened = nil }
        }
        // Новая поездка в списке — ей нужны адреса начала и конца.
        .task(id: trips.first?.persistentModelID) { await resolveAddresses() }
    }

    /// Адреса начала и конца у поездок, где их ещё нет. Геокодеру Яндекса
    /// уходят две точки маршрута (решение пользователя 08.10.2026). Не
    /// ответил — поля остаются пустыми, следующий заход на экран спросит снова.
    private func resolveAddresses() async {
        var changed = false
        // Список снят заранее: `trips` — живой запрос и за время ожидания
        // может поменяться под циклом.
        let pending = Array(trips.prefix(Self.geocoded))
        for trip in pending where trip.modelContext != nil
            && (trip.startAddress == nil || trip.endAddress == nil) {
            guard let data = trip.track,
                  let ends = TripTrack.endpoints(TripTrack.decode(data)) else { continue }
            // После каждого ожидания поездка могла исчезнуть: машину удалили
            // на другой вкладке, и каскад унёс её поездки. Запись в удалённую
            // модель SwiftData роняет приложение.
            if trip.startAddress == nil, let address = await TripGeocoder.shared.address(at: ends.start),
               trip.modelContext != nil {
                trip.startAddress = address
                changed = true
            }
            if trip.modelContext != nil, trip.endAddress == nil,
               let address = await TripGeocoder.shared.address(at: ends.end), trip.modelContext != nil {
                trip.endAddress = address
                changed = true
            }
        }
        if changed { try? modelContext.save() }
    }

    /// Поездку удалили с её экрана — правила в `TripEdits.remove`.
    private func delete(_ details: TripDetails) {
        opened = nil
        guard let trip = trips.first(where: { $0.snapshotKey == details.snapshotKey }) else { return }
        TripEdits.remove(trip, in: modelContext)
    }
}
