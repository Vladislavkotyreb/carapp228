import SwiftUI

/// «Ещё» → «Лицензии»: тексты лицензий открытых компонентов. MIT и
/// Apache 2.0 требуют отдавать их с каждой копией приложения, а не только в
/// репозитории. Текст собирается из `docs/licenses` скриптом
/// `tools/build-licenses.py` в `Licenses.txt` бандла.
struct LicensesSheet: View {
    let onClose: () -> Void

    private static let text: String = {
        guard let url = Bundle.main.url(forResource: "Licenses", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }()

    var body: some View {
        VStack(spacing: 0) {
            SheetBar(title: "Лицензии", closeSide: .trailing, onClose: onClose)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ScrollView {
                Text(Self.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Figma.graysGray)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
            }
        }
        .background(Figma.sheetBackground.ignoresSafeArea())
    }
}
