import XCTest
@testable import Beepy

/// То, без чего App Store не примет сборку или ревью её отклонит. Хост
/// тестов — само приложение, поэтому `Bundle.main` здесь — бандл Beepy.app,
/// тот же, что уйдёт в архив. Список и причины — docs/APPSTORE.md.
final class ReleaseReadinessTests: XCTestCase {
    /// ITMS-91053: бинарник зовёт «API с причиной» — причина должна быть в
    /// манифесте. Набор — по импортам бинарника, `nm -u` (docs/APPSTORE.md).
    func testPrivacyManifestDeclaresRequiredReasonAPIs() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])

        XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false)
        let declared = (plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? [])
            .compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
        for category in ["UserDefaults", "FileTimestamp", "SystemBootTime", "DiskSpace"] {
            XCTAssertTrue(declared.contains("NSPrivacyAccessedAPICategory" + category), category)
        }
    }

    /// Запрос разрешения без строки-объяснения роняет приложение.
    func testEveryPermissionHasAUsageDescription() {
        for key in ["NSMicrophoneUsageDescription",
                    "NSLocationWhenInUseUsageDescription",
                    "NSLocationAlwaysAndWhenInUseUsageDescription",
                    "NSMotionUsageDescription"] {
            let text = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
            XCTAssertFalse(text.isEmpty, key)
        }
    }

    func testExportComplianceIsDeclared() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool, false)
    }

    /// Только iPhone: с iPad App Store требует и его скриншоты, и все
    /// ориентации — экраны под это не свёрстаны.
    func testIPhoneOnly() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIDeviceFamily") as? [Int], [1])
    }

    /// MIT и Apache 2.0 — текст лицензии в каждой копии.
    func testLicensesAreBundled() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Licenses", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        for part in ["ShaderKit", "car-diagnosis", "Apache License", "Yandex MapKit"] {
            XCTAssertTrue(text.contains(part), part)
        }
    }

    /// Разбор звука идёт на устройстве. Без моделей в бандле выпуск честно
    /// отказывает — но тогда главная функция приложения не работает вовсе.
    func testDiagnosisModelsAreBundled() {
        XCTAssertTrue(LocalDiagnosis.isAvailable)
    }

    /// Выпуск без сервера не должен выдумывать машину по номеру — раньше
    /// туда шла заглушка из макета.
    func testUnavailableLookupNeverInventsACar() async {
        do {
            _ = try await UnavailableVehicleLookup().lookup(plate: "В777ОР777")
            XCTFail("поиск без сервера должен отказывать")
        } catch VehicleLookupError.unavailable {
            // так и надо
        } catch {
            XCTFail("неожиданная ошибка: \(error)")
        }
    }
}
