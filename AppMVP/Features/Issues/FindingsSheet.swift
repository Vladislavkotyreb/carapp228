import SwiftData
import SwiftUI

/// Заголовок здесь Subheadline/Emphasized (15pt), а не Body: с 17pt
/// карточка вырастала до 104 вместо заявленных в макете 102. Описание
/// ровно в две строки — в макете под него отведено 36pt, то есть 2 × 18.
/// `showAdvice` выключен по умолчанию намеренно. Тёмная карточка на экране
/// прибита к ноде макета `46093:2421` — 370×102, и третья строка выносит её
/// за эту высоту: заголовок в 17pt уже давал 104 вместо 102 и это ловилось
/// сверкой. В шторке находок высота считается по содержимому, там совет
/// и живёт — заодно это то место, где человек решает, добавлять ли находку.
struct IssueCardBody: View {
    let issue: EngineIssue
    let title: Color
    let detail: Color
    var showAdvice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(issue.title)
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.23)
                .figmaLineHeight(20, fontSize: 15, weight: .semibold)
                .foregroundStyle(title)

            Text(issue.detail)
                .font(.system(size: 13))
                .tracking(-0.08)
                .figmaLineHeight(18, fontSize: 13)
                .lineLimit(2)
                .foregroundStyle(detail)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            // Совет по расходникам — только там, где включён `showAdvice`,
            // то есть в шторке находок. На тёмной карточке экрана его нет:
            // она прибита к ноде макета 46093:2421, 370×102, третья строка
            // выносит её за высоту. Решение пользователя от 2026-09-11.
            if showAdvice, let advice = issue.advice {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "cart")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Figma.accentsYellow)
                        // Значок держит базовую линию первой строки текста:
                        // без этого он висит по центру всего блока.
                        .frame(height: 18)

                    Text(advice)
                        .font(.system(size: 13))
                        .tracking(-0.08)
                        .figmaLineHeight(18, fontSize: 13)
                        .lineLimit(3)
                        .foregroundStyle(detail)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(20)
        // Высота карточки объявлена в макете: 102. Сложением строк она не
        // получается — системные метрики SF дают 100.7, и на шестой карточке
        // список уезжает вверх на 6pt. Добор идёт снизу, поэтому текст
        // остаётся ровно там, где в макете.
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
    }
}

/// Шторка «Вот что мы нашли» (нода `46102:3369`) — вынесена из `IssuesScreen`
/// 25.09.2026 как есть, чтобы тот же флоу открывался и с главной (кнопка
/// «Послушать мотор»). Вёрстка не менялась: она сверена с макетом.
struct FindingsSheet: View {
    let findings: [EngineIssue]
    /// Разбор не услышал мотора — шторка в пустом состоянии.
    let nothingHeard: Diagnosis.HeardKind?
    let onClose: () -> Void
    let onApprove: () -> Void
    /// «Записать ещё раз» из пустого состояния.
    let onRetry: () -> Void

    /// Скругление карточки находки — то же 34, что у тёмной карточки экрана.
    private static let cardShape = RoundedRectangle(cornerRadius: 34, style: .continuous)

    // MARK: - Шторка «Вот что мы нашли» (нода 46102:3369)

    /// Форма и подача как у остальных шторок проекта — образец
    /// `AddServiceChoiceSheet`. Своя версия была голым `VStack` без контейнера:
    /// без формы, без белой заливки, без грабера и с растягивающимся
    /// `Spacer`, из-за которого кнопки уезжали за нижний край экрана.
    private static let sheetShape = UnevenRoundedRectangle(
        topLeadingRadius: 34, bottomLeadingRadius: 58,
        bottomTrailingRadius: 58, topTrailingRadius: 34
    )

    /// Геометрия шторки из ноды `46102:3369`. Вынесена в константы, потому что
    /// два числа связаны: под последней карточкой оставляется ровно блок
    /// кнопок, иначе она навсегда остаётся под ними.
    private enum Findings {
        /// Шторка занимает 812 из 874
        static let height: CGFloat = 812
        /// Тулбар: отступ сверху 16, высота 54
        static let toolbarTop: CGFloat = 16
        static let toolbarHeight: CGFloat = 54
        /// Список начинается на 86 от верха шторки, то есть через 16 после тулбара
        static let listTop: CGFloat = 16
        /// Кнопки: 54 + 12 + 54 и 22 до низа шторки — итого 142
        static let buttonsBlock: CGFloat = 142
        static let buttonsBottom: CGFloat = 22
        /// Высота растворения контента к низу. По рендеру макета оно начинается
        /// примерно на 708 и заканчивается на 804 при низе шторки 874.
        static let fadeHeight: CGFloat = 166
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Контент уходит под тулбар, тот стоит на размытии с градиентом
            // — HIG, эталон пользователя; сплошная заливка верха — косяк,
            // который уже ловили на главном экране.
            VStack(spacing: 0) {
                if let heard = nothingHeard {
                    nothingHeardState(heard)
                } else {
                    findingsList
                }
            }
            .padding(.top, Findings.toolbarTop + Findings.toolbarHeight
                     + Findings.listTop)

            sheetToolbar
                .background {
                    SheetTopBlur(tint: Figma.sheetBackground)
                        .frame(height: 118)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
        }
        .frame(height: Findings.height)
        .frame(maxWidth: .infinity)
        // Подложка сплошная, а не стекло. Лист на весь экран в iOS
        // непрозрачный, и это видно замером: сквозь `glassEffect` светил шар,
        // и фон шторки уходил в зелень. С тёмной темой поверхность стала
        // Backgrounds (Grouped)/Secondary — как у остальных шторок.
        .background(Self.sheetShape.fill(Figma.sheetBackground))
        // Без склейки в один слой `shadow` достаётся **каждому** примитиву
        // внутри по отдельности: свою тень получала каждая карточка и каждая
        // строка текста, и фон шторки уходил с 255 до 236. Раньше это гасило
        // стекло — `glassEffect` сам делает слой, — а со сплошной подложкой
        // склеивать надо руками.
        .compositingGroup()
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .overlay(alignment: .top) {
            Capsule()
                .fill(Figma.grabber)
                .frame(width: 58, height: 4)
                .padding(.top, 5)
        }
    }

    /// Разбор не нашёл мотора. Показываем **что услышали вместо него** и одну
    /// кнопку: подтверждать нечего, а «Нет, не добавлять» рядом с пустым
    /// списком читается как выбор там, где выбора нет.
    private func nothingHeardState(_ heard: Diagnosis.HeardKind) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(systemName: "waveform.badge.exclamationmark")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Figma.vibrantSecondary)

            Spacer(minLength: 0).frame(height: 20)

            Text("Двигателя не слышно")
                .font(.system(size: 22, weight: .bold))
                .figmaLineHeight(28, fontSize: 22, weight: .bold)
                .foregroundStyle(Figma.labelsPrimary)

            Spacer(minLength: 0).frame(height: 8)

            Text(heard.explanation)
                .font(.system(size: 15))
                .figmaLineHeight(20, fontSize: 15)
                .foregroundStyle(Figma.vibrantSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            Spacer(minLength: 0)

            GlassProminentButton(title: "Записать ещё раз") {
                onRetry()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, Findings.buttonsBottom)
        }
        .frame(maxWidth: .infinity)
    }

    /// Список находок с кнопками внизу.
    ///
    /// На iOS 26 кнопки объявляются панелью безопасной зоны, и система сама
    /// делает две вещи: считает отступ под них и размывает край прокрутки под
    /// панелью. Именно это размытие в макете гасит шестую карточку до 229 —
    /// нарисованным поверх градиентом такое получается только приблизительно,
    /// а системе это штатное поведение.
    @ViewBuilder
    private var findingsList: some View {
        if #available(iOS 26.0, *) {
            findingsScroll
                .safeAreaBar(edge: .bottom) {
                    findingsButtons.padding(.bottom, Findings.buttonsBottom)
                }
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            // На iOS 17–25 системного эффекта края нет: рисуем градиент сами.
            // Профиль снят с рендера макета — прозрачный к 708, почти сплошной
            // к 792, сплошной к 804 (в координатах экрана 402×874).
            findingsScroll
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    findingsButtons
                        .padding(.bottom, Findings.buttonsBottom)
                        .padding(.top, Findings.fadeHeight - Findings.buttonsBlock)
                        .background {
                            LinearGradient(
                                stops: [
                                    .init(color: Figma.sheetBackground.opacity(0), location: 0),
                                    .init(color: Figma.sheetBackground.opacity(0.9), location: 0.55),
                                    .init(color: Figma.sheetBackground, location: 0.68)
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                            .ignoresSafeArea()
                        }
                }
        }
    }

    private var findingsScroll: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                ForEach(findings) { issue in
                    IssueCardBody(issue: issue, title: Figma.labelsPrimary,
                                  detail: Figma.graysGray,
                                  showAdvice: true)
                        .background(cardSurface)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// Карточка находки на тёмной шторке. Светлую держала тень, тёмную
    /// держит заливка: Fills/Tertiary над #1C1C1E даёт ту же разницу
    /// в несколько уровней, что была у белого 255 на 252.
    private var cardSurface: some View {
        Color.clear
            .background(Self.cardShape.fill(Figma.fillsTertiary))
            .shadow(color: .black.opacity(0.10), radius: 10, y: 2)
    }

    private var findingsButtons: some View {
        VStack(spacing: 12) {
            GlassProminentButton(title: "Да, добавить ошибки", action: onApprove)
            GlassButton(title: "Нет, не добавлять", action: onClose)
        }
        .padding(.horizontal, 16)
    }

    /// Тулбар: крестик слева, заголовок по центру, чёрная галочка справа.
    private var sheetToolbar: some View {
        ZStack {
            // В пустом состоянии «нашли» — неправда: не нашли ничего.
            Text(nothingHeard == nil ? "Вот что мы нашли" : "Запись")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.43)
                .foregroundStyle(Figma.labelsPrimary)

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        // Кружок под крестиком в макете есть — Button Group со
                        // стеклом без prominent. Подача та же, что у крестика
                        // остальных шторок проекта.
                        .liquidGlass(in: Circle(), tint: Figma.sheetControl) {
                            Circle()
                                .fill(Figma.sheetControl)
                                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                        }
                .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть")

                Spacer(minLength: 0)

                if nothingHeard == nil {
                    // Белая галочка-акцент, как у остальных шторок.
                    Button(action: onApprove) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Figma.labelsPrimary))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Добавить ошибки")
                }
            }
        }
        .frame(height: Findings.toolbarHeight)
        .padding(.horizontal, 16)
        .padding(.top, Findings.toolbarTop)
    }
}

/// Разбор записи в карточки находок — общий для «Ошибок» и быстрого
/// прослушивания с главной. Вынесен из `IssuesScreen` 25.09.2026 без правок
/// логики: пороги и формулировки ниже прошли разбор с пользователем.
enum DiagnosisCards {
    /// Итог разбора: карточки или пустое состояние «мотора не слышно».
    struct Outcome {
        var cards: [EngineIssue]
        var nothingHeard: Diagnosis.HeardKind?
    }

    /// Можно ли разбирать по-настоящему. Нет — работаем на заглушке, как
    /// «Карта» без ключа.
    static var canDiagnose: Bool { LocalDiagnosis.isAvailable || DiagnosisEndpoint.isConfigured }

    /// Разбор записи целиком: локальная модель, сервер запасным путём,
    /// ошибка — карточкой. Без записи или без моделей — заглушка.
    static func run(recording: URL?) async -> Outcome {
        guard canDiagnose, let recording else {
            return Outcome(cards: IssuesStub.findings, nothingHeard: nil)
        }
        do {
            // Локальный разбор первым: модели лежат в бандле, сеть не
            // нужна вовсе. Сервер остаётся отладочным запасным путём на
            // случай сборки без моделей.
            let diagnosis = LocalDiagnosis.isAvailable
                ? try await LocalDiagnosis.diagnose(fileURL: recording)
                : try await CarDiagnosisClient.diagnose(fileURL: recording)
            var heard: Diagnosis.HeardKind?
            let cards = issues(from: diagnosis, nothingHeard: &heard)
            return Outcome(cards: cards, nothingHeard: heard)
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription
                ?? "Не удалось разобрать запись"
            return Outcome(cards: [EngineIssue(title: "Не удалось разобрать запись", detail: reason)],
                           nothingHeard: nil)
        }
    }

    /// Разбор в карточки экрана.
    ///
    /// Здесь важно не смешать два **разных** числа, которые присылает сервер.
    ///
    /// `fault_probability` — отдельная голова «есть ли вообще неисправность».
    /// Она откалибрована температурой 3.08, то есть её сырую самоуверенность
    /// специально погасили, и заявленная ошибка калибровки ≈ 0.04. Этому числу
    /// можно верить как вероятности, и оно идёт первой карточкой.
    ///
    /// `causes[].p` — это **распределение по 21 семейству**, сумма по всем
    /// единица. Температура у этой головы 1.0, то есть не калибрована вовсе.
    /// Её 99 % значат «из версий модель почти всё веса отдала этой», а вовсе не
    /// «деталь сломана с вероятностью 99 %». Поэтому в подписи стоит «модель
    /// ставит сюда», а не «уверенность»: на демо-клипе как раз выходило
    /// 99 % на выхлоп при 64 % на сам факт неисправности.
    static func issues(from diagnosis: Diagnosis,
                       nothingHeard: inout Diagnosis.HeardKind?) -> [EngineIssue] {
        guard diagnosis.modelLoaded else {
            return [EngineIssue(title: "Модель не загружена",
                                detail: "Сервер запущен без модели — запустите его "
                                        + "с ключом --model models")]
        }

        // Первый и главный предохранитель: похоже ли это вообще на мотор.
        // Модель cardiag такого вопроса не задаёт — её головы различают
        // неисправный мотор и исправный, а варианта «это не машина» у них нет.
        // Отсюда и брался «дифференциал» в тихой комнате.
        guard diagnosis.isEngine else {
            // Не карточка в общем списке: шторка целиком переходит в пустое
            // состояние. Карточка соседствовала бы с кнопками «Да, добавить
            // ошибки» — предложением добавить в историю то, чего нет.
            nothingHeard = diagnosis.heard
            return []
        }

        // Версии показываем **только** когда голова «есть ли поломка» сказала
        // «да». Она единственная здесь откалибрована, и она же единственная,
        // что умеет ответить «нет»: у головы причин класса «ничего» нет, она
        // раскладывает свои 100 % по деталям при любом входе.
        //
        // Именно на этом ловилась тишина: запись без мотора, но с парой
        // шорохов даёт два «механических» куска, вердикт при этом честный
        // «норма, 32 %», а список деталей всё равно уверенно называл выхлоп
        // на 86 %. Гейт по вердикту это снимает.
        guard diagnosis.verdict == "fault" else { return [verdictCard(diagnosis)] }

        var cards = [verdictCard(diagnosis)]

        // Хвост ранжирования — шум: модель отдаёт распределение целиком, и
        // после уверенного первого места идут доли процента. Ниже 5 % не
        // показываем: такая карточка читается как найденная неисправность.
        let ranked = diagnosis.causes.filter { $0.part != "none" && $0.p >= 0.05 }

        cards += ranked.prefix(5).map { cause in
            let part = DiagnosisVocabulary.part(cause.part)
            let zone = DiagnosisVocabulary.zone(forPart: cause.part)
            // У части семейств название совпадает с зоной («Выпускная система»),
            // и подпись выходила повтором.
            let where_ = zone == part ? "" : zone + " · "
            return EngineIssue(title: part,
                               detail: where_ + "модель ставит сюда " + percent(cause.p),
                               advice: PartAdvice.line(cause.part))
        }

        if ranked.isEmpty {
            cards.append(EngineIssue(
                title: "Конкретную деталь назвать нельзя",
                detail: "Ни одна версия не набрала веса — звука для этого мало"))
        }
        return cards
    }

    /// Первая карточка: то единственное число, которое здесь означает
    /// вероятность в обычном смысле слова.
    ///
    /// Про сегменты здесь только оговорка, а не запрет. Жёсткий запрет тут
    /// стоял и оказался вреден: порог громкости в каскаде относительный, и
    /// ровно урчащий мотор кусков не даёт так же, как тишина. Отсеивать не мотор
    /// должен привратник, а это его работа, не наша.
    static func verdictCard(_ diagnosis: Diagnosis) -> EngineIssue {
        let share = percent(diagnosis.faultProbability)
        let caveat = diagnosis.segmentCount == 0
            ? " Чистого куска звука выделить не удалось, разбор по всей записи."
            : ""

        switch diagnosis.verdict {
        case "fault":
            return EngineIssue(title: "Похоже на неисправность",
                               detail: "Оценка «что-то не так» — \(share). "
                                       + "Ниже версии, что именно, по убыванию." + caveat)
        case "normal":
            return EngineIssue(title: "Ничего тревожного не слышно",
                               detail: "Оценка «что-то не так» — \(share)." + caveat)
        default:
            return EngineIssue(title: "По этой записи не берусь судить",
                               detail: "Оценка «что-то не так» — \(share), "
                                       + "это слишком близко к середине." + caveat)
        }
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))\u{00A0}%"
    }
}

extension EngineCheck {
    /// Подтверждённые находки уходят в базу — к машине и с её пробегом.
    /// Порядок сохраняется номером: разбор ранжированный, а связь SwiftData
    /// порядок не гарантирует. Общий для «Ошибок» и быстрого прослушивания,
    /// чтобы два пути не разошлись в том, что именно пишется.
    @discardableResult
    static func record(_ issues: [EngineIssue], car: Car?, in context: ModelContext) -> EngineCheck {
        let check = EngineCheck(car: car, mileage: car?.odometer)
        context.insert(check)
        for (index, issue) in issues.enumerated() {
            let finding = EngineFinding(title: issue.title, detail: issue.detail,
                                        advice: issue.advice, order: index)
            finding.check = check
            context.insert(finding)
        }
        return check
    }
}
