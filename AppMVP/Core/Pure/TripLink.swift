import Foundation

/// Привязка машины по Bluetooth (решение пользователя 12.10.2026).
///
/// Геопозиция и датчики движения не отличают свою машину от такси: оба едут.
/// Отличает звук. Сев в свою машину, телефон подключается к её Bluetooth (или
/// CarPlay), и система отдаёт этот выход даже закрытому приложению,
/// разбуженному зоной или «значимым перемещением» (журнал с телефона,
/// 09.10.2026). Человек один раз привязывает выход к машине, сидя в ней, —
/// дальше поездка этой машины пишется, только пока её выход подключён, и
/// кончается, когда он пропал.
///
/// Разбудить приложение подключение не может: обычный Bluetooth машины не
/// маячок, и система о нём закрытому приложению не сообщает. Будят по-прежнему
/// зоны и перемещение, а привязка решает, чья это поездка и поездка ли вообще.
///
/// Здесь — решения. Выход звука читает `TripTracker`.
enum TripLink {
    // MARK: - Пороги

    /// Вышли из зоны, а Bluetooth молчит: столько ждём, не подключится ли.
    /// Магнитола подключается за секунды после запуска мотора, но бывает,
    /// что машина трогается раньше.
    static let linkWait: Double = 60
    /// Bluetooth пропал посреди поездки — через минуту она кончилась. Сразу
    /// нельзя: связь мигает, когда телефон перекладывают.
    static let linkGap: Double = 60

    // MARK: - Выход звука

    enum Kind: String, Codable, Equatable {
        /// Bluetooth: музыка, звонки, LE.
        case bluetooth
        case carPlay
        /// Динамик, провод, AirPlay — машиной не бывает.
        case other
    }

    /// Выход звука телефона — то, что из `AVAudioSession` нужно решениям.
    struct Port: Equatable {
        var kind: Kind
        /// Идентификатор выхода от системы: у Bluetooth в нём адрес устройства.
        var uid: String
        var name: String
    }

    /// Выход, привязанный к машине.
    struct Bond: Equatable {
        /// Имя машины для команд (`TripTracker.carID`).
        var carID: String
        var uid: String
        var name: String
    }

    /// Какой из текущих выходов можно привязать к машине: Bluetooth или CarPlay.
    static func bindable(_ outputs: [Port]) -> Port? {
        outputs.first { $0.kind != .other }
    }

    /// Тот ли это выход, что привязан. Сначала по идентификатору; потом по
    /// имени: музыка и звонки одной магнитолы — два выхода с разными
    /// идентификаторами и одним именем.
    static func matches(_ port: Port, uid: String, name: String) -> Bool {
        guard port.kind != .other else { return false }
        if !uid.isEmpty, port.uid == uid { return true }
        let wanted = normalized(name)
        return !wanted.isEmpty && normalized(port.name) == wanted
    }

    /// Машина, чей выход подключён сейчас. Совпадение по идентификатору
    /// сильнее совпадения по имени: две магнитолы одной марки зовутся одинаково.
    static func connected(_ outputs: [Port], bonds: [Bond]) -> String? {
        for port in outputs where port.kind != .other {
            if let bond = bonds.first(where: { !$0.uid.isEmpty && $0.uid == port.uid }) {
                return bond.carID
            }
        }
        for port in outputs {
            if let bond = bonds.first(where: { matches(port, uid: "", name: $0.name) }) {
                return bond.carID
            }
        }
        return nil
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Решение

    /// Что Bluetooth говорит о поездке.
    enum Gate: Equatable {
        /// Привязка не участвует: машина по умолчанию не привязана и ничья
        /// привязанная не подключена. Решают геопозиция и датчики, как раньше.
        case free
        /// Подключена эта машина — поездка её, что бы ни говорили датчики.
        case car(String)
        /// Машина по умолчанию привязана, а её Bluetooth молчит: такси, чужая
        /// машина, прогулка.
        case absent
    }

    /// `connected` — машина, чей выход подключён (`connected(_:bonds:)`);
    /// `defaultBound` — привязана ли машина, которой идут поездки без выбора.
    static func gate(connected: String?, defaultBound: Bool) -> Gate {
        if let connected { return .car(connected) }
        return defaultBound ? .absent : .free
    }

    /// Bluetooth привязанной поездки пропал `since` и с тех пор не вернулся —
    /// поездка кончилась.
    static func lost(since: Double?, now: Double) -> Bool {
        guard let since else { return false }
        return now - since >= linkGap
    }
}
