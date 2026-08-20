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

print("")
if failures == 0 {
    print("Все \(checks) проверок прошли.")
    exit(0)
} else {
    print("Провалено \(failures) из \(checks).")
    exit(1)
}
