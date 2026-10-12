import AppIntents
import SwiftData

/// Действия автопробега для «Быстрых команд».
///
/// Пользователь собирает из них автоматизацию: «когда телефон подключился к
/// Bluetooth машины — Начать поездку», «когда отключился — Закончить
/// поездку». Саму автоматизацию приложение создать не может — это делает
/// человек в «Командах». Кому это лишнее, включает «Автоопределение» на
/// экране «Ещё» (`TripAuto`): тогда команды не нужны, но остаются точным
/// ручным режимом — Bluetooth машины такси не подделает.

/// Машина как параметр действия. Имя — госномер: его человек узнаёт в
/// списке, и он не меняется между запусками.
struct CarEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Машина"
    static let defaultQuery = CarQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(id)")
    }
}

struct CarQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [CarEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [CarEntity] {
        let cars = try AppStore.container.mainContext
            .fetch(FetchDescriptor<Car>(sortBy: [SortDescriptor(\.createdAt)]))
        return cars.map { CarEntity(id: TripTracker.carID(of: $0), name: $0.name) }
    }
}

struct StartTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Начать поездку"
    static let description = IntentDescription("Считает километры до\u{00A0}команды «Закончить поездку».")
    static let openAppWhenRun = false

    @Parameter(title: "Машина", description: "Если машин несколько")
    var car: CarEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        do {
            try TripTracker.shared.startFromCommand(carID: car?.id)
        } catch TripTracker.Failure.needsAlways {
            throw TripIntentError.needsAlways
        } catch TripTracker.Failure.switchedOff {
            throw TripIntentError.switchedOff
        }
        return .result()
    }
}

struct EndTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Закончить поездку"
    static let description = IntentDescription("Добавляет километры поездки к\u{00A0}пробегу.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        TripTracker.shared.finish()
        return .result()
    }
}

enum TripIntentError: Error, CustomLocalizedStringResourceConvertible {
    case needsAlways
    case switchedOff

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .needsAlways: "Разрешите Beepy геопозицию «Всегда»"
        case .switchedOff: "Геопозиция выключена в\u{00A0}Beepy"
        }
    }
}

struct BeepyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartTripIntent(),
                    phrases: ["Начать поездку в \(.applicationName)"],
                    shortTitle: "Начать поездку", systemImageName: "car.fill")
        AppShortcut(intent: EndTripIntent(),
                    phrases: ["Закончить поездку в \(.applicationName)"],
                    shortTitle: "Закончить поездку", systemImageName: "flag.checkered")
    }
}
