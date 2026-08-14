import SwiftUI

/// Раздел «Ошибки» — Figma секция `46084:1942`. Три состояния одного экрана:
/// `46096:2551` (пусто), `46098:2666` (идёт запись), `46084:2014` (с историей)
/// плюс шторка `46102:3005`.
struct IssuesScreen: View {
    @StateObject private var meter = AudioLevelMeter()
    @State private var stage: Stage = .idle
    @State private var showFindings = false

    private enum Stage { case idle, recording, results }

    /// Зазор от описания до кнопки: 206 пока слушать нечего (`46096:2555`)
    /// и 48, когда снизу появилась история (`46105:4251`).
    private var buttonGap: CGFloat { stage == .results ? 48 : 206 }

    /// Верх блока: 62 + 16 у экрана с историей, 64.5 + 16 у пустого.
    private var blockTop: CGFloat { stage == .results ? 78 : 80.5 }

    /// На записи блок поднимается на карточку Liquid Glass Clear и получает
    /// внутри свои 16 отступа — контент сужается с 370 до 338 (нода
    /// `46105:4087`), а остальной экран притемняется. Это и есть та самая
    /// переработанная логика: запись больше не просто смена подписи кнопки.
    private var isLifted: Bool { stage == .recording }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                topBlock

                if stage == .results {
                    Spacer(minLength: 0).frame(height: 48)
                    history.opacity(isLifted ? 0.25 : 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, blockTop)
            .padding(.bottom, 140)
        }
        // Пока слушать нечего, прокручивать тоже нечего — иначе экран
        // оттягивается в пустоту, как это было на странице «Добавить авто».
        .scrollDisabled(stage != .results)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Figma.graysBlack)
        .animation(Motion.sheet, value: stage)
        .onDisappear { meter.stop() }
        .bottomSheet(isPresented: $showFindings) { findingsSheet }
    }

    /// Заголовок, шар, описание и кнопка. На записи всё это лежит на
    /// стеклянной карточке — отсюда внутренний отступ и своя подложка.
    private var topBlock: some View {
        VStack(spacing: 0) {
                Text("Поднесите телефон \nк двигателю")
                    .font(.system(size: 26, weight: .bold))
                    .figmaLineHeight(31.2, fontSize: 26, weight: .bold)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 0).frame(height: 48)

                SoundOrb(level: stage == .recording ? meter.level : 0)

                Spacer(minLength: 0).frame(height: 24)

                Text("Поднесите телефон к двигателю или выхлопной трубе и нажмите кнопку для начала диагностики")
                    .font(.system(size: 16))
                    .tracking(-0.31)
                    .figmaLineHeight(21, fontSize: 16)
                    .foregroundStyle(Figma.vibrantSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 0).frame(height: buttonGap)

                listenButton
        }
        .padding(isLifted ? 16 : 0)
        .background {
            if isLifted {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            }
        }
    }

    /// Своя кнопка, а не `GlassProminentButton`: тот рассчитан на светлый фон
    /// онбординга и на чёрном исчезает — остаётся голый текст без пилюли.
    /// Здесь поверхность как у тёмных карточек: заливка плюс волосяная кромка.
    private var listenButton: some View {
        Button(action: toggleRecording) {
            Text(stage == .recording ? "Стоп" : "Слушать")
                .font(.system(size: 17))
                .tracking(-0.43)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    Capsule()
                        .fill(Figma.darkCard)
                        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - История (нода 46090:2356)

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("История")
                .font(.system(size: 22, weight: .bold))
                .figmaLineHeight(28, fontSize: 22, weight: .bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0).frame(height: 20)

            statsCard

            ForEach(IssuesStub.groups) { group in
                Spacer(minLength: 0).frame(height: 24)

                Text(group.date)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.43)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(group.issues) { issue in
                    Spacer(minLength: 0).frame(height: 16)
                    issueCard(issue)
                }
            }
        }
    }

    /// Карточка со счётчиками, нода `46093:2410`: 370×96, две половины.
    private var statsCard: some View {
        HStack(spacing: 0) {
            counter(title: "Прослушиваний", value: IssuesStub.listenCount)
            counter(title: "Неисправности", value: IssuesStub.issueCount)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 26), tint: Figma.darkCard, kind: .painted) {
            RoundedRectangle(cornerRadius: 26)
                .fill(Figma.darkCard)
                .overlay(RoundedRectangle(cornerRadius: 26)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5))
        }
    }

    private func counter(title: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.08)
                .foregroundStyle(Figma.vibrantSecondary)

            Text("\(value)")
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.45)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    /// Карточка неисправности, нода `46093:2421`: 370×102, паддинг 20.
    private func issueCard(_ issue: EngineIssue) -> some View {
        Button { showFindings = true } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(issue.title)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.43)
                    .foregroundStyle(.white)

                Text(issue.detail)
                    .font(.system(size: 13))
                    .tracking(-0.08)
                    .figmaLineHeight(18, fontSize: 13)
                    .foregroundStyle(Figma.vibrantSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 26), tint: Figma.darkCard, kind: .painted) {
                RoundedRectangle(cornerRadius: 26)
                    .fill(Figma.darkCard)
                    .overlay(RoundedRectangle(cornerRadius: 26)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Шторка «вот что мы нашли» (нода 46102:3369)

    private var findingsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Итог")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.43)
                .foregroundStyle(Figma.labelsPrimary)
                .frame(maxWidth: .infinity)

            ForEach(IssuesStub.findings) { issue in
                issueCard(issue)
            }

            GlassProminentButton(title: "Записаться на ТО") { showFindings = false }
            GlassButton(title: "Закрыть") { showFindings = false }
        }
        .padding(16)
    }

    // MARK: - Действия

    private func toggleRecording() {
        switch stage {
        case .idle, .results:
            stage = .recording
            meter.start()
        case .recording:
            meter.stop()
            stage = .results
        }
    }
}

// MARK: - Данные

struct EngineIssue: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

struct IssueGroup: Identifiable {
    let id = UUID()
    let date: String
    let issues: [EngineIssue]
}

/// Заглушка. Настоящего разбора звука двигателя нет и близко: он требует
/// модели на сервере и размеченных записей. Держим отдельно, чтобы выкинуть
/// одним файлом, — так же как `StubVehicleLookup`.
enum IssuesStub {
    static let listenCount = 10
    static let issueCount = 10

    static let groups: [IssueGroup] = [
        IssueGroup(date: "15.07.2025", issues: [
            EngineIssue(title: "Проблемы с трансмиссией",
                        detail: "Проблемы с переключением передач, слышим скрежещущий звук"),
            EngineIssue(title: "Проблемы с трансмиссией",
                        detail: "Проблемы с переключением передач, слышим скрежещущий звук")
        ]),
        IssueGroup(date: "30.08.2025", issues: [
            EngineIssue(title: "Проверка системы охлаждения",
                        detail: "Температура двигателя выше нормы, возможна утечка"),
            EngineIssue(title: "Проверка системы охлаждения",
                        detail: "Температура двигателя выше нормы, возможна утечка")
        ])
    ]

    static var findings: [EngineIssue] { groups.flatMap(\.issues) }
}
