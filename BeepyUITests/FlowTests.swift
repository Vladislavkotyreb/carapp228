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
        app.launchArguments = ["-beepy-ui-test", "-beepy-test-authenticated", "-hasCompletedOnboarding", onboarded ? "YES" : "NO"]
        if seeded { app.launchArguments.append("-beepy-seed") }
        app.launch()
        return app
    }

    /// Сохранённые машины и флаг онбординга не обходят обязательный вход.
    func testSignedOutUserMustSignInEvenWithExistingCars() {
        let app = XCUIApplication()
        app.launchArguments = ["-beepy-ui-test", "-beepy-seed", "-hasCompletedOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["apple-sign-in"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Начать"].exists)
        XCTAssertFalse(app.buttons["Пробег"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Apple sign in"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSignOutReturnsToAppleSignIn() {
        let app = launch(onboarded: true, seeded: true)
        let more = app.buttons["Ещё"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        let signOut = app.buttons["Выйти из аккаунта"]
        if !signOut.isHittable { app.swipeUp() }
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "More account actions"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        signOut.tap()
        app.buttons["Выйти"].tap()
        XCTAssertTrue(app.buttons["apple-sign-in"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Пробег"].exists)
    }

    /// Снимки для карточки App Store: только тестовая база, без личных данных.
    func testAppStoreScreenshots() {
        let app = launch(onboarded: true, seeded: true)
        XCTAssertTrue(app.buttons["Пробег"].waitForExistence(timeout: 10))
        capture("01-car", app: app)
        app.swipeUp()
        capture("02-service", app: app)
        app.buttons["Машина"].tap() // expand the tab bar collapsed by scrolling
        app.buttons["Диагностика"].tap()
        capture("03-diagnosis", app: app)
        app.buttons["Карта"].tap()
        capture("04-map", app: app)
    }

    func testMapMileageCarPreview() {
        let app = launch(onboarded: true, seeded: true)
        XCTAssertTrue(app.buttons["Карта"].waitForExistence(timeout: 10))
        app.buttons["Карта"].tap()
        XCTAssertTrue(app.buttons["Список"].waitForExistence(timeout: 10))
        capture("map-mileage-car", app: app)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 3)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Системный pager, обратный свайп, стрелка и пропуск GPS остаются доступны.
    func testOnboardingPagesRemainReachable() {
        let app = launch(onboarded: false)
        XCTAssertTrue(app.buttons["onboarding-next"].waitForExistence(timeout: 10))
        capture("01-plate", app: app)
        app.buttons["onboarding-next"].tap()
        XCTAssertTrue(app.staticTexts["Послушай,\nкак она работает"].waitForExistence(timeout: 5))
        capture("02-sound", app: app)
        app.buttons["onboarding-back"].tap()
        XCTAssertTrue(app.staticTexts["Машина\nпо номеру"].waitForExistence(timeout: 5))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Послушай,\nкак она работает"].waitForExistence(timeout: 5))
        app.swipeLeft()
        XCTAssertTrue(app.buttons["onboarding-later"].waitForExistence(timeout: 5))
        capture("03-gps", app: app)
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["Послушай,\nкак она работает"].waitForExistence(timeout: 5))
        app.swipeLeft()
        XCTAssertTrue(app.buttons["Включить GPS"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists, "Геопозиция не запрашивается до нажатия")
        app.buttons["onboarding-later"].tap()
        XCTAssertTrue(app.buttons["По названию"].waitForExistence(timeout: 5))
    }

    func testGPSDeniedCanContinueLater() {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)
        app.launchArguments = ["-beepy-ui-test", "-beepy-test-authenticated", "-hasCompletedOnboarding", "NO", "-trip.auto", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding-next"].waitForExistence(timeout: 10))
        app.swipeLeft()
        app.swipeLeft()
        app.buttons["Включить GPS"].tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = system.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow", "Не разрешать", "Запретить"])).firstMatch
        XCTAssertTrue(deny.waitForExistence(timeout: 10))
        deny.tap()
        XCTAssertTrue(app.alerts["Геопозиция выключена"].waitForExistence(timeout: 10))
        app.alerts["Геопозиция выключена"].buttons["Позже"].tap()
        XCTAssertTrue(app.buttons["По названию"].waitForExistence(timeout: 5))
    }

    func testFirstLaunchToFirstCar() {
        let app = launch(onboarded: false)

        XCTAssertTrue(app.buttons["onboarding-next"].waitForExistence(timeout: 10))
        app.swipeLeft()
        app.swipeLeft()
        app.buttons["onboarding-later"].tap()

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

    /// Ручное добавление третьей машины открывается без подписки.
    func testThirdCarCanBeAddedByName() {
        let app = launch(onboarded: true, seeded: true)
        XCTAssertTrue(app.buttons["Пробег"].waitForExistence(timeout: 10))

        let addCard = app.buttons["Добавить авто"]
        app.swipeLeft()
        XCTAssertTrue(addCard.waitForExistence(timeout: 5))
        addCard.tap()

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
        // В шторке у поля пробега есть следующее — цена: первый «ввод» ведёт
        // туда, второй, на последней строке, отправляет форму. Кнопку
        // «Добавить» под полями закрывает клавиатура, а системную галочку
        // панели XCUITest видит за верхним краем экрана и нажать не может.
        mileage.typeText("\n")
        app.typeText("\n")
        XCTAssertTrue(app.staticTexts["Kia Rio"].waitForExistence(timeout: 10))

        app.swipeLeft()
        XCTAssertTrue(addCard.waitForExistence(timeout: 5))
        addCard.tap()
        XCTAssertTrue(byName.waitForExistence(timeout: 5))
        byName.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Toyota Camry")
        mileage.tap()
        typeSlowly("50000", into: mileage)
        mileage.typeText("\n")
        app.typeText("\n")
        XCTAssertTrue(app.staticTexts["Toyota Camry"].waitForExistence(timeout: 10))

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

    /// «Ещё» → «О приложении» → «Лицензии»: тексты открытых компонентов
    /// внутри приложения.
    func testLicensesAreReachable() {
        let app = launch(onboarded: true, seeded: true)

        let more = app.buttons["Ещё"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()

        // «Лицензии» — на экране «О приложении», строкой корня «Ещё».
        let about = app.buttons["О\u{00A0}приложении"]
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.tap()

        let licenses = app.buttons["Лицензии"]
        XCTAssertTrue(licenses.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Условия использования сервиса Яндекс.Карты"].exists)
        XCTAssertTrue(app.buttons["Условия использования API Яндекс Карт"].exists)
        let aboutShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        aboutShot.name = "about-yandex-links"
        aboutShot.lifetime = .keepAlways
        add(aboutShot)
        licenses.tap()

        let shaderKit = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ShaderKit")).firstMatch
        XCTAssertTrue(shaderKit.waitForExistence(timeout: 5))
    }
}
