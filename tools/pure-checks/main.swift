import Foundation

// Проверки чистого слоя `AppMVP/Core/Pure`. Запуск — tools/run-pure-checks.sh.
//
// Это не XCTest: тестового таргета в проекте нет, а Xcode есть не на всякой
// машине. Здесь достаточно swiftc из Command Line Tools, поэтому проверки
// доступны везде и прямо сейчас.
//
// Побочный смысл важнее прямого: файлы `Core/Pure` компилируются здесь **без**
// SwiftUI, SwiftData и UIKit. Затащишь их туда — перестанет собираться этот
// прогон, а не приложение через неделю. Это и есть граница слоя.

var failures = 0
var checks = 0

func check<T: Equatable>(_ name: String, _ got: T, _ want: T) {
    checks += 1
    if got != want {
        failures += 1
        print("  ✗ \(name)\n      получили: \(got)\n      ожидали:  \(want)")
    }
}

func group(_ title: String, _ body: () -> Void) {
    print("\(title)")
    body()
}

// ---------------------------------------------------------------- PlateFormat

group("PlateFormat") {
    check("латиница становится кириллицей и пробелы расставляются",
          PlateFormat.format("b777op777"), "В 777 ОР 777")
    check("кириллица на входе проходит как есть",
          PlateFormat.format("в777ор777"), "В 777 ОР 777")
    check("уже отформатированный номер не ломается",
          PlateFormat.format("В 777 ОР 777"), "В 777 ОР 777")
    check("десятый значащий символ не влезает",
          PlateFormat.format("b777op7777"), "В 777 ОР 777")
    check("цифра на месте буквы отбрасывается",
          PlateFormat.significant("7777"), "")
    check("буква без кириллического двойника отбрасывается",
          PlateFormat.significant("Zв777ор777"), "В777ОР777")

    check("полный номер с трёхзначным регионом валиден",
          PlateFormat.isValid("b777op777"), true)
    check("двузначный регион валиден", PlateFormat.isValid("В 777 ОР 77"), true)
    check("однозначный регион невалиден", PlateFormat.isValid("В 777 ОР 7"), false)
    check("пустая строка невалидна", PlateFormat.isValid(""), false)

    let parts = PlateFormat.components("b777op777")
    check("разбор: буква", parts?.letter, "В")
    check("разбор: три цифры", parts?.digits, "777")
    check("разбор: две буквы", parts?.letters, "ОР")
    check("разбор: регион", parts?.region, "777")
    check("разбор двузначного региона",
          PlateFormat.components("В777ОР77")?.region, "77")
    check("короткий номер не разбирается",
          PlateFormat.components("В777ОР7")?.region, nil)
}

// ---------------------------------------------------------------- ServiceMath

group("ServiceMath") {
    check("без истории ТО — полный интервал",
          ServiceMath.kmUntilService(odometer: 50_000, serviceMileages: []), 10_000)
    check("проехали половину интервала",
          ServiceMath.kmUntilService(odometer: 55_000, serviceMileages: [50_000]), 5_000)
    check("просроченное ТО показывает 0, а не долг",
          ServiceMath.kmUntilService(odometer: 65_000, serviceMileages: [50_000]), 0)
    check("отсчёт идёт от самого свежего ТО, а не от последнего в массиве",
          ServiceMath.kmUntilService(odometer: 52_000,
                                     serviceMileages: [40_000, 50_000, 45_000]), 8_000)
    check("ровно на интервале — 0",
          ServiceMath.kmUntilService(odometer: 60_000, serviceMileages: [50_000]), 0)

    check("прогресс: половина", ServiceMath.progress(odometer: 55_000,
                                                     serviceMileages: [50_000]), 0.5)
    check("прогресс не переваливает за 1",
          ServiceMath.progress(odometer: 70_000, serviceMileages: [50_000]), 1.0)
    check("одометр меньше пробега на ТО — прогресс 0, а не отрицательный",
          ServiceMath.progress(odometer: 45_000, serviceMileages: [50_000]), 0.0)
    check("без истории прогресс 0",
          ServiceMath.progress(odometer: 50_000, serviceMileages: []), 0.0)

    check("итого по пустой истории", ServiceMath.totalSpent(amounts: []), 0)
    check("итого по работам", ServiceMath.totalSpent(amounts: [12_000, 3_500, 450]), 15_950)

    check("одометр не опускается ниже текущего",
          ServiceMath.odometerAfterService(current: 50_000, serviceMileage: 48_000), 50_000)
    check("ТО с большим пробегом поднимает одометр",
          ServiceMath.odometerAfterService(current: 50_000, serviceMileage: 52_000), 52_000)
}

// --------------------------------------------------------------- NumberFormat

group("NumberFormat") {
    let nbsp = "\u{00A0}"
    check("разряды через неразрывный пробел",
          NumberFormat.grouped(9_000_000), "9\(nbsp)000\(nbsp)000")
    check("три цифры не разделяются", NumberFormat.grouped(999), "999")
    check("ноль", NumberFormat.grouped(0), "0")

    check("разбор строки с валютой", NumberFormat.digits("12 000 ₽"), 12_000)
    check("пустая строка — nil", NumberFormat.digits(""), nil)
    check("строка без цифр — nil", NumberFormat.digits("₽"), nil)
    check("минус отбрасывается: пробег отрицательным не бывает",
          NumberFormat.digits("-500"), 500)
    check("запасное значение подставляется",
          NumberFormat.digits("абв", or: 42), 42)
    check("запасное значение не мешает разбору",
          NumberFormat.digits("777", or: 42), 777)

    // Главная проверка пары: разбор обязан понимать то, что напечатал вывод.
    // Разделитель там неразрывный, и обычный `filter` его не заметил бы.
    check("вывод и разбор сходятся на неразрывном пробеле",
          NumberFormat.digits(NumberFormat.grouped(1_234_567)), 1_234_567)
}

// ------------------------------------------------------------- IssuesPhase

group("IssuesPhase.of") {
    check("покой без истории — пустой экран",
          IssuesPhase.of(activity: .idle, hasHistory: false), .empty)
    check("покой с историей — экран с историей",
          IssuesPhase.of(activity: .idle, hasHistory: true), .history)
    check("запись на пустом экране идёт на месте, без модалки",
          IssuesPhase.of(activity: .recording, hasHistory: false), .recordingInline)
    check("запись поверх истории — модалка",
          IssuesPhase.of(activity: .recording, hasHistory: true), .recordingModal)
    check("разбор выглядит одинаково без истории",
          IssuesPhase.of(activity: .analyzing, hasHistory: false), .analyzing)
    check("разбор выглядит одинаково с историей",
          IssuesPhase.of(activity: .analyzing, hasHistory: true), .analyzing)

    // Каждая фаза обязана быть достижимой. Фаза, которую не производит ни одно
    // сочетание, — кадр в галерее, которого в приложении не бывает: галерея
    // объявляет себя полным набором состояний и врёт.
    var reachable: Set<IssuesPhase> = []
    for activity in IssuesActivity.allCases {
        for hasHistory in [true, false] {
            reachable.insert(IssuesPhase.of(activity: activity, hasHistory: hasHistory))
        }
    }
    check("каждая фаза достижима из какого-то состояния",
          Set(IssuesPhase.allCases).subtracting(reachable).map(\.rawValue).sorted(), [])

    // Обратное тоже: фаза, которой нет в типе, не может быть произведена —
    // это гарантирует компилятор, а здесь фиксируется число.
    check("сочетаний шесть, фаз пять", reachable.count, IssuesPhase.allCases.count)

    // Модалка появляется ровно там, где раньше стояло `isRecording && hasHistory`.
    // Правило переехало в тип, и вот доказательство, что смысл не поменялся.
    for activity in IssuesActivity.allCases {
        for hasHistory in [true, false] {
            let phase = IssuesPhase.of(activity: activity, hasHistory: hasHistory)
            check("модалка = запись и есть история (\(activity.rawValue), \(hasHistory))",
                  phase == .recordingModal, activity == .recording && hasHistory)
        }
    }
}

// ------------------------------- Эквивалентность старой и новой машин ------
//
// `IssuesScreen` переведён с двух булевых на одно значение. Собрать
// приложение на этой машине нечем, поэтому равенство поведения доказывается
// здесь: обе машины прогоняются на всех последовательностях событий, и на
// каждом шаге сравниваются те два флага, которые читает вёрстка.
//
// Модели — копии кода переходов, а не импорт: `IssuesScreen` живёт в SwiftUI
// и сюда не собирается. Расхождение модели с кодом ловится глазами при
// правке, и это записано как ограничение.

enum UIEvent: String, CaseIterable {
    case tap        // нажатие «Слушать» / «Стоп»
    case finish     // разбор вернул ответ
    case disappear  // ушли с раздела
}

/// Как было: два независимых флага.
struct OldMachine {
    var rec = false
    var ana = false
    /// Настроен ли сервер: без него разбор не начинается вовсе.
    let configured: Bool

    mutating func handle(_ event: UIEvent) {
        switch event {
        case .tap:
            if rec { rec = false; if configured { ana = true } }
            else { rec = true }
        case .finish:
            if ana { ana = false }
        case .disappear:
            break   // флаги оставались как есть — отсюда и залипание
        }
    }
}

/// Как стало: одно значение.
struct NewMachine {
    var activity: IssuesActivity = .idle
    let configured: Bool

    var rec: Bool { activity == .recording }
    var ana: Bool { activity == .analyzing }

    mutating func handle(_ event: UIEvent) {
        switch event {
        case .tap:
            if rec { activity = .idle; if configured { activity = .analyzing } }
            else { activity = .recording }
        case .finish:
            if ana { activity = .idle }
        case .disappear:
            activity = .idle
        }
    }
}

group("IssuesScreen: старая и новая машины состояний") {
    // Кнопка отключена на время разбора (`.disabled(isAnalyzing)`), поэтому
    // нажатие в этот момент недостижимо и в переборе не порождается.
    func sequences(_ depth: Int) -> [[UIEvent]] {
        guard depth > 0 else { return [[]] }
        return sequences(depth - 1).flatMap { tail in
            UIEvent.allCases.map { [$0] + tail }
        }
    }

    for configured in [true, false] {
        var mismatches: [String] = []
        var reachedAnalyzing = false
        for seq in sequences(6) {
            var old = OldMachine(configured: configured)
            var new = NewMachine(configured: configured)
            var sawDisappear = false
            for event in seq {
                if event == .tap && old.ana { continue }   // кнопка отключена
                if event == .disappear { sawDisappear = true }
                old.handle(event)
                new.handle(event)
                if new.ana { reachedAnalyzing = true }
                // До ухода с раздела поведение обязано совпадать полностью.
                if !sawDisappear && (old.rec != new.rec || old.ana != new.ana) {
                    mismatches.append("\(seq.map(\.rawValue).joined(separator: ">")) "
                                      + "старая(\(old.rec),\(old.ana)) "
                                      + "новая(\(new.rec),\(new.ana))")
                }
            }
        }
        check("поведение совпадает на всех последовательностях "
              + "(сервер \(configured ? "настроен" : "не настроен"))",
              mismatches.first, nil)
        check("разбор вообще достижим в переборе (сервер \(configured))",
              reachedAnalyzing, configured)
    }

    // Единственное намеренное расхождение — уход с раздела. Старая машина
    // оставляла флаг, и кнопка возвращалась отключённой навсегда.
    var old = OldMachine(configured: true)
    var new = NewMachine(configured: true)
    for event in [UIEvent.tap, .tap, .disappear] { old.handle(event); new.handle(event) }
    check("старая машина залипала в разборе после ухода", old.ana, true)
    check("новая возвращается в покой", new.activity, .idle)

    var oldRec = OldMachine(configured: true)
    var newRec = NewMachine(configured: true)
    for event in [UIEvent.tap, .disappear] { oldRec.handle(event); newRec.handle(event) }
    check("старая машина залипала в записи после ухода", oldRec.rec, true)
    check("новая возвращается в покой и здесь", newRec.activity, .idle)

    // Незаконное сочетание в новой машине невыразимо по построению: проверяем,
    // что перебор его действительно ни разу не производит.
    var illegal = 0
    for seq in sequences(6) {
        var m = NewMachine(configured: true)
        for event in seq {
            if event == .tap && m.ana { continue }
            m.handle(event)
            if m.rec && m.ana { illegal += 1 }
        }
    }
    check("«записываю и разбираю» не встречается ни разу", illegal, 0)
}

// ------------------------------------------------------------ UIStateCatalog

group("UIStateCatalog") {
    let ids = UIStateCatalog.all.map(\.id)

    // Главная проверка: каталог обязан совпадать с типами. Добавил случай
    // в enum — здесь краснеет, пока у случая нет кадра. Без этого «все
    // состояния» через месяц восстанавливают по памяти, и экраны теряются.
    let have = Set(ids)
    let want = Set(UIStateCatalog.required)
    check("у каждого случая типа есть состояние в каталоге",
          want.subtracting(have).sorted(), [])
    check("в каталоге нет состояний без случая в типе",
          have.subtracting(want).sorted(), [])

    check("идентификаторы уникальны", ids.count, have.count)
    check("каталог не пуст", ids.isEmpty, false)

    // id — это имя PNG и имя фрейма Figma одновременно. Пробел или заглавная
    // в начале ломают замену картинок при переснятии.
    let shape = ids.filter { id in
        let parts = id.split(separator: "-")
        guard parts.count == 2, let head = parts.first, let tail = parts.last else { return true }
        return !(head.allSatisfy { $0.isLowercase }
                 && tail.first?.isLowercase == true
                 && tail.allSatisfy { $0.isLetter || $0.isNumber })
    }
    check("идентификаторы вида «экран-состояние»", shape.sorted(), [])

    check("у каждого состояния назван экран",
          UIStateCatalog.all.filter { $0.screen.isEmpty }.map(\.id), [])
    check("у каждого состояния есть описание",
          UIStateCatalog.all.filter { $0.what.isEmpty }.map(\.id), [])

    // Нода макета либо есть в виде «12345:678», либо честно отсутствует.
    let badNode = UIStateCatalog.all.compactMap { entry -> String? in
        guard let node = entry.node else { return nil }
        let parts = node.split(separator: ":")
        let valid = parts.count == 2 && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
        return valid ? nil : entry.id
    }
    check("ноды записаны как «12345:678»", badNode.sorted(), [])

    // Сообщения ошибок поля не должны совпадать: одинаковый текст у двух
    // случаев означает, что один из них на экране неотличим от другого.
    let messages = FieldError.allCases.map(\.message)
    check("у каждой ошибки поля свой текст", messages.count, Set(messages).count)
}

print("")
print("Состояний в каталоге: \(UIStateCatalog.all.count), "
      + "из них без ноды макета: \(UIStateCatalog.withoutNode.count).")

print("")
if failures == 0 {
    print("Все \(checks) проверок прошли.")
    exit(0)
} else {
    print("Провалено \(failures) из \(checks).")
    exit(1)
}
