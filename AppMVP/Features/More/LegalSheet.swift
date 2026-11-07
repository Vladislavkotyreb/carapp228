import SwiftUI

/// «Ещё» → «Политика конфиденциальности» и «Условия использования»: текст
/// документа из `LegalDocument`, без сети. Подача та же, что у лицензий, —
/// системный лист с панелью и прокруткой.
struct LegalSheet: View {
    let document: LegalDocument
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SheetBar(title: document.title, closeSide: .trailing, onClose: onClose)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Редакция от \(document.updated)")
                        .font(.system(size: 13))
                        .foregroundStyle(Figma.graysGray)

                    ForEach(document.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Figma.labelsPrimary)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                                blockView(block)
                            }
                        }
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .background(Figma.sheetBackground.ignoresSafeArea())
    }

    @ViewBuilder
    private func blockView(_ block: LegalBlock) -> some View {
        switch block {
        case .text(let text):
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Figma.labelsSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .item(let lead, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .foregroundStyle(Figma.labelsSecondary)
                // Начало пункта белым — список читается по первым словам.
                Text("\(Text(lead).foregroundStyle(Figma.labelsPrimary)) \(Text(text).foregroundStyle(Figma.labelsSecondary))")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 15))
        }
    }
}
