import SwiftUI

/// Шторка «Что расскажем сервису» — между кнопкой «Записаться» и картой
/// (вариант D из секции «Прослушивания» в Figma, выбран пользователем
/// 25.09.2026). Собирает то, что сервису нужно для записи: машину и пробег,
/// последнее прослушивание мотора и последнее ТО.
///
/// Сервера нет, поэтому «рассказать» пока значит отправить сводку самому:
/// кнопкой «Поделиться» или в мессенджер с карточки сервиса. Те же поля потом
/// придут в CRM заявкой, и текст собирает `ListeningSummary.message`.
struct BookingSummarySheet: View {
    /// Всё, что шторка показывает, — значениями: модели SwiftData сюда не
    /// заходят, переходник `Car → Model` живёт в `CarMainView`.
    struct Model {
        let carTitle: String
        let carSubtitle: String
        let check: CheckInfo?
        let lastService: (title: String, subtitle: String)?
        /// Текст сводки: с прослушиванием и без — выбирает переключатель.
        let messageWithCheck: String
        let messageWithoutCheck: String
    }

    struct CheckInfo {
        let title: String
        let subtitle: String
        let findings: [String]
        let isStale: Bool
    }

    private static let shape = UnevenRoundedRectangle(
        topLeadingRadius: 34, bottomLeadingRadius: 58,
        bottomTrailingRadius: 58, topTrailingRadius: 34
    )
    private static let rowShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    let model: Model
    let onClose: () -> Void
    let onFindService: () -> Void
    let onListen: () -> Void

    /// Приложить ли прослушивание. Устаревшее по умолчанию не прикладываем:
    /// старый диагноз может увести мастера не туда, пусть человек решит сам.
    @State private var attachCheck: Bool

    init(model: Model, onClose: @escaping () -> Void,
         onFindService: @escaping () -> Void, onListen: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        self.onFindService = onFindService
        self.onListen = onListen
        _attachCheck = State(initialValue: model.check.map { !$0.isStale } ?? false)
    }

    var body: some View {
        VStack(spacing: 16) {
            toolbar

            VStack(spacing: 8) {
                row(symbol: "car.fill", tint: .white, title: model.carTitle, subtitle: model.carSubtitle)
                checkRow
                if let service = model.lastService {
                    row(symbol: "wrench.and.screwdriver.fill", tint: .white,
                        title: service.title, subtitle: service.subtitle)
                }
            }

            VStack(spacing: 4) {
                GlassProminentButton(title: "Найти сервис", lineHeight: 18, action: onFindService)

                ShareLink(item: attachCheck ? model.messageWithCheck : model.messageWithoutCheck) {
                    Label("Отправить сводку", systemImage: "square.and.arrow.up")
                        .font(.system(size: 15))
                        .foregroundStyle(Figma.labelsPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .liquidGlass(in: Self.shape, tint: Figma.sheetBackground) {
            Self.shape.fill(Figma.sheetBackground)
        }
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .overlay(alignment: .top) {
            Capsule()
                .fill(Figma.vibrantPrimary)
                .frame(width: 58, height: 4)
                .padding(.top, 5)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    // MARK: - Строки

    @ViewBuilder
    private var checkRow: some View {
        if let check = model.check {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    icon("waveform", tint: Figma.accentsYellow)
                    texts(title: check.title, subtitle: check.subtitle)
                    Toggle("Приложить прослушивание", isOn: $attachCheck)
                        .labelsHidden()
                        .tint(Figma.accentsGreen)
                }

                if !check.findings.isEmpty {
                    chips(check.findings)
                        .padding(.leading, 48)
                        .opacity(attachCheck ? 1 : 0.4)
                }

                if check.isStale {
                    listenHint("Слушали больше \(ListeningSummary.staleAfterDays)\u{00A0}дней назад — лучше послушать заново")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Figma.fillsQuaternary, in: Self.rowShape)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    icon("waveform", tint: Figma.graysGray)
                    texts(title: ListeningSummary.title(days: nil),
                          subtitle: "Сервис узнает только машину и\u{00A0}пробег")
                }
                listenHint("Послушайте мотор — в\u{00A0}заявку уйдёт готовый диагноз")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Figma.fillsQuaternary, in: Self.rowShape)
        }
    }

    private func row(symbol: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            icon(symbol, tint: tint)
            texts(title: title, subtitle: subtitle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Figma.fillsQuaternary, in: Self.rowShape)
    }

    private func icon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(Figma.fillsTertiary, in: Circle())
    }

    private func texts(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Figma.labelsSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Находки капсулами: две первые и «+N». Больше в строку не влезает, а
    /// полный список человек видел в «Ошибках» — здесь он только напоминание.
    private func chips(_ findings: [String]) -> some View {
        // Прокрутка, а не обрезка: «Подшипник генерато…» терял главное слово.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(findings.prefix(2), id: \.self) { chip($0) }
                if findings.count > 2 { chip("+\(findings.count - 2)") }
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Figma.labelsPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            // Fills/Tertiary, а не цвет контролов шторки: строка уже лежит
            // на заливке, и капсула того же тона в ней пропадала (кадр 25.09).
            .background(Figma.fillsTertiary, in: Capsule())
    }

    private func listenHint(_ text: String) -> some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Figma.labelsSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onListen) {
                // Вторичная кнопка: серая заливка и обычное начертание
                // (правка пользователя 26.09.2026 — жёлтая спорила с «Найти
                // сервис», хотя действие второстепенное).
                Text("Послушать")
                    .font(.system(size: 13))
                    .foregroundStyle(Figma.labelsPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Figma.fillsTertiary, in: Capsule())
                    // Видно 32, нажимается 44 — HIG.
                    .contentShape(Rectangle().inset(by: -6))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 48)
    }

    // MARK: - Тулбар

    private var toolbar: some View {
        ZStack {
            Text("Что расскажем сервису")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.43)
                .foregroundStyle(Figma.vibrantControlsPrimary)

            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .liquidGlass(in: Circle(), tint: Figma.sheetControl) {
                            Circle()
                                .fill(Figma.sheetControl)
                                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть")
            }
        }
        .frame(height: 44)
    }
}
