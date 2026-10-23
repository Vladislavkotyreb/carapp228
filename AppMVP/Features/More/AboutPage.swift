import SwiftUI

/// «Ещё» → «О приложении»: политика, условия и лицензии. App Store требует
/// ссылку на политику внутри приложения, MIT и Apache — тексты лицензий в
/// каждой копии. Политика и условия открываются листом из текста в
/// приложении (`LegalDocument`), а не страницей сервера: сервера ещё нет, а
/// строка нужна с первой сборки. Внизу версия: по ней сверяют сборку при
/// жалобе.
struct AboutPage: View {
    /// Открытый документ: политика или условия.
    @State private var legal: LegalDocument?
    @State private var licensesShown = false

    var body: some View {
        MorePage(title: "О\u{00A0}приложении") {
            VStack(alignment: .leading, spacing: 12) {
                MoreCard {
                    ForEach(LegalDocument.allCases) { document in
                        MoreLinkRow(title: document.title) { legal = document }
                        MoreSeparator()
                    }
                    MoreLinkRow(title: "Лицензии") { licensesShown = true }
                }

                MoreFootnote("Версия \(Self.version)")
            }
        }
        .sheet(item: $legal) { document in
            LegalSheet(document: document) { legal = nil }
        }
        .sheet(isPresented: $licensesShown) {
            LicensesSheet { licensesShown = false }
                .presentationDragIndicator(.visible)
        }
    }

    /// «1.0.0 (1)» — версия и номер сборки из бандла.
    static let version: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }()
}
