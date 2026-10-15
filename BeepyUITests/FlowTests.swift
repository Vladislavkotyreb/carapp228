import XCTest

/// Ключевые флоу глазами пользователя. Приложение стартует с
/// `-beepy-ui-test` — база в памяти (`UITestLaunch` в TripTracker.swift),
/// данные симулятора не трогаются; `-beepy-seed` — машина «Lada Vesta» с
/// пробегом 120 000 и одним ТО на 115 000. Онбординг включается и
/// выключается аргументом `-hasCompletedOnboarding` — он перекрывает
/// UserDefaults на время запуска.
///
/// Это и есть «проверка жестов»: раньше тапать по симулятору было нечем
/// (osascript без Универсального доступа), а XCUITest ходит в приложение сам.
final class FlowTests: XCTestCase {
    private let nbsp = "\u{00A0}"

    override func setUp() {
        continueAfterFailure = false
        // Системный вопрос о разрешении перекрыл бы экран теста.
        addUIInterruptionMonitor(withDescription: "Разрешения") { alert in
            for title in ["Разрешить при использовании", "Allow While Using App", "Разрешить", "Allow", "OK"] {
                let button = alert.buttons[title]
                if button.exists { button.tap(); return true }
            }
            return false
        }
    }

    private func launch(onboarded: Bool, seeded: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-beepy-ui-test", "-hasCompletedOnboarding", onboarded ? "YES" : "NO"]
        if seeded { app.launchArguments.append("-beepy-seed") }
        app.launch()
        return app
    }

    /// Первый запуск: «Начать» вместо снятого «Войти с Apple», опрос можно
    /// пропустить, машина по названию появляется на главной.
    func testFirstLaunchToFirstCar() {
        let app = launch(onboarded: false)

        let start = app.buttons["Начать"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Sign in with Apple"].exists)
        start.tap()

        // Первая страница — то, что приложение умеет сейчас.
        XCTAssertTrue(app.staticTexts["Пробег считается сам"].waitForExistence(timeout: 5))
        let skip = app.buttons["Пропустить"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        let byName = app.buttons["По названию"]
        XCTAssertTrue(byName.waitForExistence(timeout: 5))
        byName.tap()

        let name = app.textFields["Название"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Kia Rio")
        let mileage = app.textFields["Пробег, км"]
        mileage.tap()
        typeSlowly("85000", into: mileage)
        XCTAssertEqual(mileage.value as? String, "85\(nbsp)000",
                       "маска разрядов не должна путать порядок цифр")
        // «Добавить» под экранной клавиатурой — отправляем с неё, как человек.
        mileage.typeText("\n")

        XCTAssertTrue(app.staticTexts["Kia Rio"].waitForExistence(timeout: 10))
    }

    /// По цифре с паузой — как набирает человек. Пачкой `typeText` печатает
    /// быстрее, чем маска успевает переставить курсор, и в поле выходит
    /// чепуха, которой у человека не бывает.
    private func typeSlowly(_ text: String, into field: XCUIElement) {
        for character in text {
            field.typeText(String(character))
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    /// Пробег ниже последнего ТО не сохраняется: причина под полем, галочка
    /// погашена (правка 14.10.2026, «ТО через 99 799 999 км»).
    func testMileageBelowLastServiceIsRejected() {
        let app = launch(onboarded: true, seeded: true)

        let tile = app.buttons["Пробег"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        let pencil = app.buttons["Изменить цену"]
        XCTAssertTrue(pencil.waitForExistence(timeout: 5))
        pencil.tap()

        // В поле подставлен текущий пробег 120 000 — стереть и ввести меньше ТО.
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 9))
        app.typeText("110000")

        XCTAssertTrue(app.staticTexts["Меньше, чем на\(nbsp)последнем ТО"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Сохранить цену"].isEnabled)

        // А не меньше ТО — можно.
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 9))
        app.typeText("121000")
        XCTAssertTrue(app.buttons["Сохранить цену"].isEnabled)
    }

    /// Карточка ТО в истории: сумма и пробег, на котором ТО прошли.
    func testServiceCardShowsMileage() {
        let app = launch(onboarded: true, seeded: true)
        let headline = app.staticTexts["4\(nbsp)500\(nbsp)₽ · 115\(nbsp)000\(nbsp)км"]
        XCTAssertTrue(app.buttons["Пробег"].waitForExistence(timeout: 10))
        for _ in 0..<4 where !headline.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
    }

    /// «Ещё» → «Лицензии»: тексты открытых компонентов внутри приложения.
    func testLicensesAreReachable() {
        let app = launch(onboarded: true, seeded: true)

        let more = app.buttons["Ещё"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()

        let licenses = app.buttons["Лицензии"]
        for _ in 0..<6 where !licenses.isHittable {
            app.swipeUp()
        }
        licenses.tap()

        let shaderKit = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ShaderKit")).firstMatch
        XCTAssertTrue(shaderKit.waitForExistence(timeout: 5))
    }
}
