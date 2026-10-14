import Foundation
import Security
import SwiftData
import UIKit

/// Синхронизация поездок и пробега с сервером Beepy (`server/`, решение
/// пользователя 12.10.2026). Выключена, пока человек сам не включит её в
/// «Ещё» и не согласится на обработку данных: до этого ничего не уходит.
///
/// Аккаунт анонимный: токен устройства лежит в Связке ключей iCloud, и с ним
/// новый айфон того же Apple ID попадает в тот же аккаунт без входа. Что
/// уходит и как решаются конфликты — `SyncPlan`.
@MainActor
final class TripSync: ObservableObject {
    static let shared = TripSync()

    enum Status: Equatable {
        case idle
        case syncing
        case done(Date)
        case failed(String)
    }

    enum Failure: Error, Equatable {
        case noServer
        case consentOutdated
        case unauthorized
        case server(Int)
        case offline
    }

    /// Синхронизацию поездок не выкатываем (решение пользователя 14.10.2026):
    /// переезд на новый айфон закрывает резервная копия iPhone, а польза
    /// появится, когда CRM понадобится пробег клиента. Код и сервер остаются;
    /// выключено — раздела в «Ещё» нет и ничего не уходит, даже в симуляторе.
    static let isShipped = false

    /// Редакция согласия, которую принимает человек. Меняется вместе с
    /// текстом `SyncConsentSheet` и `CONSENT_VERSION` сервера.
    static let consentVersion = "2026-10-12"
    static let enabledKey = "sync.enabled"

    @Published private(set) var status: Status = .idle
    @Published private(set) var isOn = UserDefaults.standard.bool(forKey: TripSync.enabledKey)
    /// Аккаунт на сервере есть: даже с выключенной синхронизацией его
    /// можно удалить.
    @Published private(set) var hasAccount = SyncKeychain.token != nil

    private var pending: Task<Void, Never>?
    private var running = false
    /// Чаще раза в пять минут при открытии приложения не синхронизируем.
    private static let foregroundGap: TimeInterval = 300

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameActive() }
        }
    }

    /// Адрес сервера — общий для всего приложения (`BeepyServer`).
    static var serverURL: URL? { BeepyServer.url }

    // MARK: - Включить и выключить

    /// Человек согласился: завести аккаунт (если токена ещё нет) и сразу
    /// синхронизировать.
    func enable() async throws {
        if SyncKeychain.token == nil { try await register() }
        isOn = true
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        await syncNow()
    }

    /// Выключить: дальше ничего не уходит. Данные на сервере остаются —
    /// удаляет их отдельная кнопка.
    func disable() {
        pending?.cancel()
        isOn = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        status = .idle
    }

    /// Удалить аккаунт на сервере со всеми машинами и поездками. На телефоне
    /// всё остаётся.
    func deleteFromServer() async throws {
        if SyncKeychain.token != nil {
            do {
                _ = try await request("DELETE", "/v1/account", body: Optional<Int>.none, as: Empty.self)
            } catch Failure.unauthorized {
                // Аккаунта уже нет — то, чего и хотели.
            }
        }
        forgetAccount()
        disable()
    }

    /// Что-то поменялось в поездках: синхронизировать через пару секунд,
    /// собрав подряд идущие правки в один запрос.
    func changed() {
        guard Self.isShipped, isOn else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    private func becameActive() {
        guard Self.isShipped, isOn else { return }
        if case .done(let at) = status, Date.now.timeIntervalSince(at) < Self.foregroundGap { return }
        Task { await syncNow() }
    }

    // MARK: - Синхронизация

    func syncNow() async {
        guard Self.isShipped, isOn, !running else { return }
        running = true
        status = .syncing
        defer { running = false }
        do {
            try await run()
            status = .done(.now)
        } catch Failure.unauthorized {
            // Устройство отозвали в админке или аккаунт удалён: токен
            // бесполезен, синхронизация выключается до нового согласия.
            forgetAccount()
            disable()
            status = .failed("Отключено на сервере")
        } catch Failure.offline {
            status = .failed("Нет связи с сервером")
        } catch {
            status = .failed("Не получилось")
        }
    }

    private func run() async throws {
        let context = AppStore.container.mainContext
        var state = SyncState.load()
        // Пачками: сервер берёт до 500 поездок за раз и отдаёт историю
        // страницами. Пятьдесят пачек — 25 тысяч поездок; дальше —
        // следующая синхронизация.
        for _ in 0..<50 {
            let cars = try context.fetch(FetchDescriptor<Car>())
            let trips = try context.fetch(FetchDescriptor<Trip>())
            var assigned = false
            for car in cars where car.syncID == nil { car.syncID = UUID(); assigned = true }
            for trip in trips where trip.syncID == nil { trip.syncID = UUID(); assigned = true }
            if assigned { try context.save() }

            let carPlan = SyncPlan.outgoing(cars.map(Self.record), synced: state.cars,
                                            id: \.id, print: SyncPlan.fingerprint)
            let tripPlan = SyncPlan.outgoing(trips.map(Self.record), synced: state.trips,
                                             id: \.id, print: SyncPlan.fingerprint)
            let now = Date.now
            let sendCars = Array((carPlan.changed.map { WireCar($0, at: now) }
                                  + carPlan.deleted.map { WireCar(tombstone: $0, at: now) })
                .prefix(SyncPlan.carsPerRequest))
            let sendTrips = Array((tripPlan.changed.map { WireTrip($0, at: now) }
                                   + tripPlan.deleted.map { WireTrip(tombstone: $0, at: now) })
                .prefix(SyncPlan.tripsPerRequest))
            let leftover = carPlan.changed.count + carPlan.deleted.count > sendCars.count
                || tripPlan.changed.count + tripPlan.deleted.count > sendTrips.count

            let reply = try await request(
                "POST", "/v1/sync",
                body: SyncBody(cursor: SyncPlan.validCursor(state.cursor), cars: sendCars, trips: sendTrips),
                as: SyncReply.self)

            for car in sendCars {
                guard let id = UUID(uuidString: car.id) else { continue }
                if car.deleted {
                    state.cars[id] = nil
                } else if let sent = carPlan.changed.first(where: { $0.id == id }) {
                    state.cars[id] = SyncPlan.fingerprint(sent)
                }
            }
            for trip in sendTrips {
                guard let id = UUID(uuidString: trip.id) else { continue }
                if trip.deleted {
                    state.trips[id] = nil
                } else if let sent = tripPlan.changed.first(where: { $0.id == id }) {
                    state.trips[id] = SyncPlan.fingerprint(sent)
                }
            }
            try apply(reply, to: &state, in: context)
            state.cursor = reply.cursor
            state.save()
            if !leftover && !reply.more { return }
        }
    }

    /// Что вернул сервер — уже итог спора: правки с других устройств и
    /// отвергнутые наши. Берём как есть.
    private func apply(_ reply: SyncReply, to state: inout SyncState, in context: ModelContext) throws {
        guard !reply.cars.isEmpty || !reply.trips.isEmpty else { return }
        var cars = Dictionary(try context.fetch(FetchDescriptor<Car>()).compactMap { car in
            car.syncID.map { ($0, car) }
        }, uniquingKeysWith: { first, _ in first })

        for incoming in reply.cars {
            guard let id = UUID(uuidString: incoming.id) else { continue }
            if incoming.deleted {
                if let car = cars[id] { context.delete(car) }
                cars[id] = nil
                state.cars[id] = nil
                continue
            }
            let car = cars[id] ?? {
                // Машина с другого телефона: номера и VIN на сервере нет.
                let made = Car(plate: "", name: incoming.name, odometer: incoming.odometer)
                made.syncID = id
                context.insert(made)
                return made
            }()
            car.name = incoming.name
            car.odometer = incoming.odometer
            car.trackedKm = incoming.trackedKm
            cars[id] = car
            state.cars[id] = SyncPlan.fingerprint(Self.record(car))
        }

        let trips = Dictionary(try context.fetch(FetchDescriptor<Trip>()).compactMap { trip in
            trip.syncID.map { ($0, trip) }
        }, uniquingKeysWith: { first, _ in first })
        for incoming in reply.trips {
            guard let id = UUID(uuidString: incoming.id),
                  let started = Wire.date(incoming.startedAt), let ended = Wire.date(incoming.endedAt) else { continue }
            if incoming.deleted {
                // Пробег не трогаем: он приходит записью машины.
                if let trip = trips[id] {
                    TripSnapshots.remove(for: trip.snapshotKey)
                    context.delete(trip)
                }
                state.trips[id] = nil
                continue
            }
            let car = incoming.carId.flatMap(UUID.init(uuidString:)).flatMap { cars[$0] }
            let trip = trips[id] ?? {
                let made = Trip(startedAt: started, endedAt: ended, meters: incoming.meters, car: car)
                made.syncID = id
                context.insert(made)
                return made
            }()
            trip.startedAt = started
            trip.endedAt = ended
            trip.meters = incoming.meters
            trip.auto = incoming.auto
            trip.car = car
            state.trips[id] = SyncPlan.fingerprint(Self.record(trip))
        }
        try context.save()
    }

    private static func record(_ car: Car) -> SyncPlan.Car {
        SyncPlan.Car(id: car.syncID ?? UUID(), name: car.name.isEmpty ? "Машина" : car.name,
                     odometer: max(0, car.odometer), trackedKm: max(0, car.trackedKm ?? 0))
    }

    private static func record(_ trip: Trip) -> SyncPlan.Trip {
        SyncPlan.Trip(id: trip.syncID ?? UUID(), carID: trip.car?.syncID, startedAt: trip.startedAt,
                      endedAt: max(trip.endedAt, trip.startedAt), meters: min(max(0, trip.meters), 2_000_000),
                      auto: trip.auto ?? false)
    }

    // MARK: - Аккаунт

    private func register() async throws {
        let device = UIDevice.current
        let body = RegisterBody(
            consentVersion: Self.consentVersion,
            device: .init(model: Self.hardwareModel, os: "\(device.systemName) \(device.systemVersion)",
                          appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
        let reply = try await request("POST", "/v1/accounts", body: body, as: RegisterReply.self, authorized: false)
        SyncKeychain.token = reply.token
        SyncState().save()
        hasAccount = true
    }

    private func forgetAccount() {
        SyncKeychain.token = nil
        SyncState.remove()
        hasAccount = false
    }

    /// «iPhone16,1», а не «iPhone»: по нему в админке видно модель.
    private static var hardwareModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    // MARK: - Сеть

    private func request<Body: Encodable, Reply: Decodable>(
        _ method: String, _ path: String, body: Body?, as: Reply.Type, authorized: Bool = true
    ) async throws -> Reply {
        guard let base = Self.serverURL else { throw Failure.noServer }
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized {
            guard let token = SyncKeychain.token else { throw Failure.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.offline
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200..<300:
            if Reply.self == Empty.self, let empty = Empty() as? Reply { return empty }
            return try JSONDecoder().decode(Reply.self, from: data)
        case 401: throw Failure.unauthorized
        case 409: throw Failure.consentOutdated
        default: throw Failure.server(code)
        }
    }
}

// MARK: - Что лежит между запусками

/// Курсор сервера и отпечатки отправленного. Файлом рядом с базой: в
/// `UserDefaults` тысячи отпечатков разрастались бы при каждом запуске.
private struct SyncState: Codable {
    var cursor: String?
    var cars: [UUID: String] = [:]
    var trips: [UUID: String] = [:]

    private static let url = URL.applicationSupportDirectory.appending(path: "sync-state.json")

    static func load() -> SyncState {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(SyncState.self, from: $0) } ?? SyncState()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Токен устройства — в Связке ключей с синхронизацией через iCloud: новый
/// телефон того же Apple ID получает его сам и попадает в тот же аккаунт.
enum SyncKeychain {
    private static let service = "com.vladislavkotyrev.appmvp.sync"
    private static let account = "device-token"

    static var token: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let match: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ]
            SecItemDelete(match as CFDictionary)
            guard let newValue, let data = newValue.data(using: .utf8) else { return }
            let item: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: true,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                kSecValueData as String: data,
            ]
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}

// MARK: - Формат запросов

private enum Wire {
    static let format: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(_ date: Date) -> String { format.string(from: date) }
    static func date(_ string: String) -> Date? { format.date(from: string) }
}

private struct WireCar: Codable {
    var id: String
    var name: String
    var odometer: Int
    var trackedKm: Int
    var updatedAt: String
    var deleted: Bool

    init(_ car: SyncPlan.Car, at date: Date) {
        id = car.id.uuidString.lowercased()
        name = car.name
        odometer = car.odometer
        trackedKm = car.trackedKm
        updatedAt = Wire.string(date)
        deleted = false
    }

    /// Удаление: поля серверу уже не нужны, но формат их требует.
    init(tombstone id: UUID, at date: Date) {
        self.id = id.uuidString.lowercased()
        name = "—"
        odometer = 0
        trackedKm = 0
        updatedAt = Wire.string(date)
        deleted = true
    }
}

private struct WireTrip: Codable {
    var id: String
    var carId: String?
    var startedAt: String
    var endedAt: String
    var meters: Double
    var auto: Bool
    var updatedAt: String
    var deleted: Bool

    init(_ trip: SyncPlan.Trip, at date: Date) {
        id = trip.id.uuidString.lowercased()
        carId = trip.carID?.uuidString.lowercased()
        startedAt = Wire.string(trip.startedAt)
        endedAt = Wire.string(trip.endedAt)
        meters = trip.meters
        auto = trip.auto
        updatedAt = Wire.string(date)
        deleted = false
    }

    /// `carId: null` — явным null: поездка без машины всё равно несёт поле.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(carId, forKey: .carId)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(meters, forKey: .meters)
        try container.encode(auto, forKey: .auto)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deleted, forKey: .deleted)
    }

    private enum CodingKeys: String, CodingKey {
        case id, carId, startedAt, endedAt, meters, auto, updatedAt, deleted
    }

    init(tombstone id: UUID, at date: Date) {
        self.id = id.uuidString.lowercased()
        carId = nil
        startedAt = Wire.string(date)
        endedAt = Wire.string(date)
        meters = 0
        auto = false
        updatedAt = Wire.string(date)
        deleted = true
    }
}

private struct SyncBody: Encodable {
    var cursor: String?
    var cars: [WireCar]
    var trips: [WireTrip]

    // `cursor: null` — явным null: сервер ждёт поле, а не его отсутствие.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cursor, forKey: .cursor)
        try container.encode(cars, forKey: .cars)
        try container.encode(trips, forKey: .trips)
    }

    private enum CodingKeys: String, CodingKey { case cursor, cars, trips }
}

private struct SyncReply: Decodable {
    var cursor: String
    var more: Bool
    var cars: [WireCar]
    var trips: [WireTrip]
}

private struct RegisterBody: Encodable {
    struct Device: Encodable {
        var model: String
        var os: String
        var appVersion: String
    }

    var consentVersion: String
    var device: Device
}

private struct RegisterReply: Decodable {
    var token: String
}

private struct Empty: Codable {}
