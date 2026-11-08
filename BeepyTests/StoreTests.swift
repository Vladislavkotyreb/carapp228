import SwiftData
import XCTest
@testable import Beepy

/// База SwiftData: схема собирается, удаление машины уносит её историю,
/// испорченный файл не роняет приложение.
///
/// Чистый слой (`Core/Pure`) здесь не повторяется — его 560+ проверок
/// гоняет `tools/run-pure-checks.sh` без Xcode. Эти тесты — про то, что тот
/// прогон не видит: модели, диск, бандл, экраны.
@MainActor
final class StoreTests: XCTestCase {
    func testAddressCacheExpiresWithoutRemovingTrip() throws {
        let container = AppStore.inMemory()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let trip = Trip(startedAt: now, endedAt: now, meters: 1234, car: nil, track: Data([1, 2]))
        trip.startAddress = "legacy"
        trip.endAddress = "fresh"
        trip.endAddressFetchedAt = now.addingTimeInterval(-60)
        context.insert(trip)
        try context.save()
        try Trip.clearExpiredAddresses(in: context, now: now)
        XCTAssertNil(trip.startAddress)
        XCTAssertEqual(trip.endAddress, "fresh")
        try Trip.clearExpiredAddresses(in: context, now: now.addingTimeInterval(AddressCache.lifetime))
        XCTAssertNil(trip.endAddress)
        XCTAssertNil(trip.endAddressFetchedAt)
        XCTAssertEqual(trip.meters, 1234)
        XCTAssertEqual(trip.track, Data([1, 2]))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Trip>()), 1)
        XCTAssertFalse(AddressCache.isFresh(now.addingTimeInterval(1), now: now))
        XCTAssertFalse(AddressCache.isFresh(now, now: now.addingTimeInterval(AddressCache.lifetime)))
        XCTAssertTrue(AddressCache.isFresh(now, now: now.addingTimeInterval(AddressCache.lifetime - 1)))
    }

    func testSchemaOpensInMemory() throws {
        // Контейнер — в переменной: контекст его не удерживает, и временный
        // контейнер, освободившись, уронил бы процесс на первой записи.
        let container = AppStore.inMemory()
        let context = container.mainContext
        context.insert(Car(plate: "", name: "Проверка", odometer: 1))
        XCTAssertNoThrow(try context.save())
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Car>()), 1)
    }

    /// Сироты в SwiftData — запись ТО без машины — уже стоили полдня
    /// (docs/TRAPS.md). Каскад держится моделью, тест держит модель.
    func testDeletingCarRemovesItsHistory() throws {
        let container = AppStore.inMemory()
        let context = container.mainContext
        let car = Car(plate: "", name: "Проверка", odometer: 10_000)
        let record = ServiceRecord(date: .now, mileage: 9_000)
        record.works = [ServiceWorkItem(title: "Масло", amount: 3_000)]
        record.car = car
        let trip = Trip(startedAt: .now.addingTimeInterval(-600), endedAt: .now, meters: 5_000, car: car)
        context.insert(car)
        context.insert(record)
        context.insert(trip)
        try context.save()

        context.delete(car)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Car>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ServiceRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ServiceWorkItem>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Trip>()), 0)
    }

    /// Раньше на этом месте был `fatalError`: приложение падало на каждом
    /// запуске, пока файл не удалят руками.
    func testCorruptStoreIsMovedAsideAndAFreshOneOpens() throws {
        let dir = try temporaryDirectory()
        let url = dir.appending(path: "default.store")
        try Data("это не база SQLite".utf8).write(to: url)

        let (container, recovery) = AppStore.open(at: url)

        XCTAssertEqual(recovery, .movedAside)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("default.store.broken-") },
                      "сломанный файл должен остаться рядом: из него можно достать данные")
        container.mainContext.insert(Car(plate: "", name: "После сбоя", odometer: 1))
        XCTAssertNoThrow(try container.mainContext.save())
    }

    func testHealthyStoreKeepsDataBetweenOpens() throws {
        let url = try temporaryDirectory().appending(path: "default.store")
        do {
            let (container, recovery) = AppStore.open(at: url)
            XCTAssertNil(recovery)
            container.mainContext.insert(Car(plate: "", name: "Сохранится", odometer: 42))
            try container.mainContext.save()
        }
        let (again, recovery) = AppStore.open(at: url)
        XCTAssertNil(recovery)
        let cars = try again.mainContext.fetch(FetchDescriptor<Car>())
        XCTAssertEqual(cars.map(\.name), ["Сохранится"])
    }

    func testPlateLimitCountsOnlyPlateCarsIncludingPendingInserts() throws {
        let container = AppStore.inMemory()
        let context = container.mainContext
        for index in 0..<4 {
            context.insert(Car(plate: "", name: "Manual \(index)", odometer: 0))
        }
        XCTAssertTrue(Car.canAddByPlate(in: context))
        context.insert(Car(plate: "А111АА77", name: "First", odometer: 0))
        XCTAssertTrue(Car.canAddByPlate(in: context))
        let second = Car(plate: "А222АА77", name: "Second", odometer: 0)
        context.insert(second)
        XCTAssertFalse(Car.canAddByPlate(in: context))
        try context.save()
        XCTAssertFalse(Car.canAddByPlate(in: context))
        context.delete(second)
        try context.save()
        XCTAssertTrue(Car.canAddByPlate(in: context))
    }

    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
}
