import Foundation

/// Один снимок галереи состояний.
struct UIStateEntry: Equatable {
    /// Имя PNG и имя фрейма в Figma одновременно. **Не переименовывать:**
    /// на нём держится замена картинок при переснятии.
    let id: String
    /// Экран, к которому относится состояние.
    let screen: String
    /// Что именно видно — строкой, которую можно прочитать под кадром.
    let what: String
    /// Нода макета, если она известна. `nil` — состояния в макете нет:
    /// либо это наш случай (ошибка сервера), либо дизайн ещё не нарисован.
    let node: String?
}

/// Каталог состояний интерфейса — данные, а не код галереи.
///
/// Зачем он отдельно от вью: «все состояния» иначе восстанавливают по памяти,
/// и так теряются экраны. Шесть из семи исходов шторки находок в приложении
/// никто не видел — они требуют определённых ответов сервера, и без списка
/// рядом о них просто не вспомнить.
///
/// Список **обязан совпадать с типами** из `UIState.swift`: `required`
/// собирается из `allCases`, а проверки сверяют его с `all`. Добавил случай
/// в тип — прогон краснеет, пока у случая нет кадра. Это единственное, что
/// не даёт каталогу разойтись с приложением.
///
/// Чего проверки **не** ловят: новый тип состояния целиком. Его надо добавить
/// в `required` руками — как и в исходном приёме, откуда он перенесён.
enum UIStateCatalog {

    static let all: [UIStateEntry] = onboarding + addCar + fieldErrors
        + car + serviceSheets + issues + findings + map + tabBar

    // MARK: - Онбординг

    static let onboarding: [UIStateEntry] = [
        .init(id: "onboarding-welcome", screen: "Онбординг",
              what: "Приветствие и «Войти с Apple»", node: "45822:3994"),
        .init(id: "onboarding-survey1", screen: "Онбординг",
              what: "Опрос 1 — отмечай любимые места", node: nil),
        .init(id: "onboarding-survey2", screen: "Онбординг",
              what: "Опрос 2 — следи за звуками", node: "45825:2235"),
        .init(id: "onboarding-survey3", screen: "Онбординг",
              what: "Опрос 3 — записывай результаты ТО", node: "45826:2283"),
    ]

    // MARK: - Добавление машины

    static let addCar: [UIStateEntry] = [
        .init(id: "addcar-plateEmpty", screen: "Добавление машины",
              what: "Вкладка «По номеру», поле пустое", node: "45854:2880"),
        .init(id: "addcar-plateFilled", screen: "Добавление машины",
              what: "Номер введён полностью, кнопка активна", node: nil),
        .init(id: "addcar-searching", screen: "Добавление машины",
              what: "Идёт поиск: индикатор поверх скрытого лейбла", node: nil),
        .init(id: "addcar-found", screen: "Добавление машины",
              what: "Шторка «Это ваш автомобиль?»", node: "45854:2936"),
        .init(id: "addcar-byName", screen: "Добавление машины",
              what: "Вкладка «По названию», поля пустые", node: nil),
        .init(id: "addcar-byNameFilled", screen: "Добавление машины",
              what: "Название, пробег и фото заполнены", node: nil),
    ]

    /// Каждая ошибка поля — свой кадр: они отличаются только строкой, и
    /// именно поэтому расхождение с макетом здесь никто не замечает.
    static let fieldErrors: [UIStateEntry] = [
        .init(id: "fielderror-plateInvalid", screen: "Добавление машины",
              what: "Номер короче девяти символов: тряска поля", node: nil),
        .init(id: "fielderror-plateNotFound", screen: "Добавление машины",
              what: "Номера нет в базе — состояние недостижимо на заглушке", node: nil),
        .init(id: "fielderror-detailsMissing", screen: "Добавление машины",
              what: "Не заполнены название и пробег", node: nil),
        .init(id: "fielderror-lookupFailed", screen: "Добавление машины",
              what: "Поставщик не ответил", node: nil),
    ]

    // MARK: - Раздел «Машина»

    static let car: [UIStateEntry] = [
        .init(id: "car-noHistory", screen: "Машина",
              what: "История ТО пуста, прокрутки нет", node: "45949:3477"),
        .init(id: "car-withHistory", screen: "Машина",
              what: "«ТО через», «Всего потрачено», лента записей", node: "45867:3007"),
        .init(id: "car-scrolled", screen: "Машина",
              what: "Список прокручен: чёрная шапка, свайп заперт", node: "46001:6457"),
        .init(id: "car-addPage", screen: "Машина",
              what: "Последняя страница карусели — «Добавить авто»", node: "45949:3265"),
        .init(id: "car-noPhoto", screen: "Машина",
              what: "Машина без фото", node: nil),
    ]

    static let serviceSheets: [UIStateEntry] = [
        .init(id: "service-choice", screen: "Добавление ТО",
              what: "Выбор способа: фото/PDF или вручную", node: "45883:3842"),
        .init(id: "service-manualEmpty", screen: "Добавление ТО",
              what: "Ручной ввод, одна пустая работа", node: "45870:2868"),
        .init(id: "service-manualFilled", screen: "Добавление ТО",
              what: "Несколько работ и приложенный чек", node: nil),
        .init(id: "service-editing", screen: "Добавление ТО",
              what: "Правка существующей записи", node: nil),
        .init(id: "service-parsed", screen: "Добавление ТО",
              what: "Форма заполнена разбором фото/PDF (заглушка)", node: nil),
    ]

    // MARK: - Раздел «Ошибки»

    static let issues: [UIStateEntry] = [
        .init(id: "issues-empty", screen: "Ошибки",
              what: "История пуста, зазор до кнопки 206", node: "46096:2555"),
        .init(id: "issues-history", screen: "Ошибки",
              what: "История есть, зазор до кнопки 48", node: "46105:4251"),
        .init(id: "issues-recordingInline", screen: "Ошибки",
              what: "Запись на пустом экране, без модалки", node: nil),
        .init(id: "issues-recordingModal", screen: "Ошибки",
              what: "Запись модалкой поверх притемнённой истории", node: "46105:3970"),
        .init(id: "issues-analyzing", screen: "Ошибки",
              what: "Запись отдана на разбор, кнопка держит индикатор", node: nil),
    ]

    /// Шторка находок. Шесть исходов из семи на экране никто не видел.
    static let findings: [UIStateEntry] = [
        .init(id: "findings-stub", screen: "Шторка находок",
              what: "Сервер не настроен — шесть карточек заглушки", node: "46102:3369"),
        .init(id: "findings-serverWithoutModel", screen: "Шторка находок",
              what: "Сервер поднят без модели", node: nil),
        .init(id: "findings-notEngine", screen: "Шторка находок",
              what: "Привратник не услышал мотора", node: nil),
        .init(id: "findings-fault", screen: "Шторка находок",
              what: "«Похоже на неисправность» плюс версии по убыванию", node: nil),
        .init(id: "findings-normal", screen: "Шторка находок",
              what: "«Ничего тревожного не слышно», версий нет", node: nil),
        .init(id: "findings-uncertain", screen: "Шторка находок",
              what: "Вердикт посередине, судить не берёмся", node: nil),
        .init(id: "findings-failed", screen: "Шторка находок",
              what: "Сеть или разбор отказали", node: nil),
    ]

    // MARK: - Прочее

    static let map: [UIStateEntry] = [
        .init(id: "map-noKey", screen: "Карта",
              what: "Ключ MapKit не задан — объяснение вместо пустоты", node: nil),
        .init(id: "map-live", screen: "Карта",
              what: "Карта с позицией пользователя", node: nil),
        .init(id: "map-list", screen: "Карта",
              what: "Список: избранное, свои точки и найденное рядом", node: nil),
        .init(id: "map-listEmpty", screen: "Карта",
              what: "Список, в котором нечего показать", node: nil),
    ]

    static let tabBar: [UIStateEntry] = [
        .init(id: "tabbar-expanded", screen: "Таббар",
              what: "Развёрнут, ширины поровну", node: nil),
        .init(id: "tabbar-minimized", screen: "Таббар",
              what: "Свёрнут в пилюлю активной вкладки", node: nil),
    ]

    // MARK: - Что обязано быть, по типам

    /// Идентификаторы, выведенные из `allCases`. Сверяются с `all`.
    static var required: [String] {
        OnboardingStep.allCases.map { "onboarding-\($0.rawValue)" }
        + AddCarPhase.allCases.map { "addcar-\($0.rawValue)" }
        + FieldError.allCases.map { "fielderror-\($0.rawValue)" }
        + CarPhase.allCases.map { "car-\($0.rawValue)" }
        + ServiceSheet.allCases.map { "service-\($0.rawValue)" }
        + IssuesPhase.allCases.map { "issues-\($0.rawValue)" }
        + FindingsOutcome.allCases.map { "findings-\($0.rawValue)" }
        + MapPhase.allCases.map { "map-\($0.rawValue)" }
        + TabBarPhase.allCases.map { "tabbar-\($0.rawValue)" }
    }

    /// Состояния, которых нет в макете: их не с чем сверять, и это надо знать
    /// до редизайна, а не посреди него.
    static var withoutNode: [UIStateEntry] { all.filter { $0.node == nil } }
}
