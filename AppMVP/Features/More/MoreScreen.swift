import SwiftData
import SwiftUI

/// Раздел «Ещё»: короткий список, каждая строка — свой экран.
///
/// Раньше всё лежало одной лентой: карточка автопробега, настройка,
/// синхронизация, история поездок и «О приложении». Пользователь назвал это
/// перегрузом (23.10.2026) — теперь на корне три строки со значением
/// справа, а содержимое открывается экраном: «Автопробег»
/// (`AutoMileagePage`, вместе с геопозицией, доступом и Bluetooth — они нужны
/// только ему), «Поездки» (`TripsPage`), «О приложении» (`AboutPage`).
/// Между ними — «Связаться»: Telegram и почта разработчика открываются сразу.
///
/// Тексты короткие намеренно (замечание пользователя 08.10.2026: «поменьше
/// текста, выглядит нейронно»): подпись там, где без неё непонятно, что
/// делать, и нигде больше.
struct MoreScreen: View {
    @ObservedObject private var tracker = TripTracker.shared
    @Query private var trips: [Trip]
    @Environment(\.openURL) private var openURL
    @AppStorage(LocationSwitch.key) private var locationOn = true
    @AppStorage(AutoSwitch.key) private var autoOn = false

    private enum Page: Hashable {
        case auto, trips, about
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: MoreLayout.section) {
                    GroupedCard {
                        link("Автопробег", value: autoValue, highlighted: autoHighlighted, to: .auto)
                        GroupedSeparator()
                        link("Поездки", value: trips.isEmpty ? "Нет" : "\(trips.count)", to: .trips)
                    }

                    // Написать разработчику — прямо с корня, без захода в «О
                    // приложении» (просьба пользователя 23.10.2026).
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle("Связаться")
                        GroupedCard {
                            GroupedLinkRow(title: "Telegram", value: "@\(DeveloperContact.telegram)") {
                                if let url = DeveloperContact.telegramURL { openURL(url) }
                            }
                            GroupedSeparator()
                            GroupedLinkRow(title: "Почта", value: DeveloperContact.email) {
                                if let url = DeveloperContact.mailURL { openURL(url) }
                            }
                        }
                    }

                    GroupedCard {
                        link("О\u{00A0}приложении", value: AboutPage.version, to: .about)
                    }
                }
                .padding(.horizontal, MoreLayout.margin)
                .padding(.top, 8)
                .padding(.bottom, MoreLayout.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Figma.backgroundsPrimary.ignoresSafeArea())
            .navigationTitle("Ещё")
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .auto: AutoMileagePage()
                case .trips: TripsPage()
                case .about: AboutPage()
                }
            }
        }
        // На корне, а не на экране автопробега: выключатель живёт там, а
        // трекер должен узнать о нём, даже когда экран уже закрыт.
        .onChange(of: locationOn) { _, _ in tracker.locationSwitched() }
    }

    /// Идёт поездка — это главное, что стоит видеть с корня.
    private var autoValue: String {
        if tracker.active != nil { return "Идёт поездка" }
        return locationOn && autoOn ? "Включён" : "Выключен"
    }

    private var autoHighlighted: Bool {
        tracker.active != nil || (locationOn && autoOn)
    }

    private func link(_ title: String, value: String, highlighted: Bool = false, to page: Page) -> some View {
        NavigationLink(value: page) {
            GroupedRowLabel(title: title, value: value, highlighted: highlighted, icon: "chevron.right")
        }
        .buttonStyle(CardPressStyle())
        // Название — подписью, значение — значением: VoiceOver читает
        // «Поездки, 12», а тест находит строку по названию.
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

// MARK: - Каркас экранов раздела

/// Размеры экранов раздела: поля экрана 16, зазор между группами 32,
/// кнопка 52. Строки и группы — `GroupedLayout`.
enum MoreLayout {
    static let margin: CGFloat = 16
    static let section: CGFloat = 32
    static let button: CGFloat = 52
    /// Под плавающий таббар на iOS до 26.
    static let tail: CGFloat = 110
}

/// Экран раздела: прокрутка, поля и заголовок в панели навигации.
struct MorePage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: MoreLayout.section) {
                content
            }
            .padding(.horizontal, MoreLayout.margin)
            .padding(.top, 8)
            .padding(.bottom, MoreLayout.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Figma.backgroundsPrimary.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
