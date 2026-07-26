import PhotosUI
import SwiftUI

/// Figma «добавление машины + edge cases» (секция 45854:2880).
/// Один экран с двумя вкладками и состояниями ошибок; координаты из макета
/// (контейнер y = 107.93, высота 735, паддинг 16, кнопка прижата к низу).
struct AddCarView: View {
    @EnvironmentObject private var appState: AppState

    /// Если задан — экран открыт модально (добавление ещё одной машины),
    /// и по завершении просто закрывается, не сбрасывая уже добавленную.
    var onFinish: (() -> Void)?

    @State private var tab = 0
    @State private var plate = ""
    @State private var name = ""
    @State private var mileage = ""
    @State private var fieldError: FieldError?
    @State private var shake: CGFloat = 0
    @State private var foundCar: FoundCar?
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: Image?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Figma.backgroundsPrimary

            VStack(spacing: 0) {
                VStack(spacing: 36) {
                    Text("Добавь авто")
                        .font(.system(size: Figma.titleSize, weight: .bold))
                        .figmaLineHeight(Figma.titleLineHeight, fontSize: Figma.titleSize, weight: .bold)
                        .foregroundStyle(Figma.labelsPrimary)
                        .frame(maxWidth: .infinity)

                    if tab == 0 { byPlate } else { byName }
                }

                Spacer(minLength: 0)

                GlassProminentButton(title: "Добавить", action: submit)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 735, alignment: .top)
            .offset(y: 107.93)

            if let foundCar {
                Figma.overlaysDefault
                    .ignoresSafeArea()

                CarFoundSheet(
                    car: foundCar,
                    onClose: { self.foundCar = nil },
                    onConfirm: { finish() },
                    onReject: {
                        self.foundCar = nil
                        fieldError = .plateNotFound
                    }
                )
                .offset(x: 6, y: 137.93)
            }
        }
        .ignoresSafeArea()
        .animation(Motion.sheet, value: foundCar != nil)
        // отклик даёт SwiftUI — он уважает системные настройки
        .sensoryFeedback(.error, trigger: shake)
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    photo = Image(uiImage: uiImage)
                }
            }
        }
    }

    // MARK: - Вкладка «По номеру»

    private var byPlate: some View {
        VStack(spacing: 32) {
            segmentedControl

            VStack(spacing: 8) {
                FigmaTextField(
                    placeholder: "В 777 ОР 777",
                    text: $plate,
                    placeholderColor: fieldError == nil ? Figma.labelsQuaternary : Figma.labelsTertiary,
                    keyboardType: .asciiCapable,
                    format: PlateFormat.format,
                    autocapitalization: .characters
                )
                .shake(shake)

                if let fieldError {
                    caption(fieldError.message, color: Figma.accentsRed)
                }
            }
        }
    }

    // MARK: - Вкладка «По названию»

    private var byName: some View {
        VStack(spacing: 24) {
            VStack(spacing: 32) {
                segmentedControl

                VStack(spacing: 8) {
                    FigmaGroupedTextField(
                        firstPlaceholder: "Название",
                        first: $name,
                        secondPlaceholder: "Пробег в км",
                        second: $mileage,
                        secondKeyboardType: .numberPad,
                        bottomPadding: fieldError == nil ? 19 : 0
                    )
                    .shake(shake)

                    if let fieldError {
                        caption(fieldError.message, color: Figma.accentsRed)
                    }
                }
            }

            if let photo {
                VStack(spacing: 20) {
                    photo
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 26))

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        FigmaRowLabel(systemImage: "photo", title: "Выбрать другое фото")
                    }
                }
            } else {
                VStack(spacing: 8) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        FigmaRowLabel(systemImage: "photo", title: "Выбрать фото")
                    }

                    caption("Сфотографируйте машину спереди для лучшего вида", color: Figma.labelsTertiary)
                }
            }
        }
    }

    private var segmentedControl: some View {
        FigmaSegmentedControl(titles: ["По номеру", "По названию"], selection: $tab)
            .onChange(of: tab) { _, _ in fieldError = nil }
    }

    private func caption(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12))
            .figmaLineHeight(16, fontSize: 12)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Действия

    private func submit() {
        if tab == 0 {
            let symbols = PlateFormat.significant(plate)
            if !PlateFormat.isValid(plate) {
                fail(.plateInvalid)
            } else if symbols == "В777ОР777" {
                // TODO: заменить на реальный поиск по API — сейчас данные из макета.
                fieldError = nil
                foundCar = .designExample(plate: plate)
            } else {
                fail(.plateNotFound)
            }
        } else {
            if name.trimmingCharacters(in: .whitespaces).isEmpty
                || mileage.trimmingCharacters(in: .whitespaces).isEmpty {
                fail(.detailsMissing)
            } else {
                fieldError = nil
                finish()
            }
        }
    }

    private func finish() {
        if let onFinish { onFinish() } else { appState.completeCarAdding() }
    }

    /// Аннотация в макете: «хаптик негативное действие и тряска инпута».
    private func fail(_ error: FieldError) {
        fieldError = error
        withAnimation(.linear(duration: 0.4)) { shake += 1 }
    }
}

enum FieldError {
    case plateInvalid
    case plateNotFound
    case detailsMissing

    var message: String {
        switch self {
        case .plateInvalid: return "Введите госномер: буква, 3 цифры, 2 буквы и код региона"
        case .plateNotFound: return "Мы не нашли такого номера в базе, попробуйте другой"
        case .detailsMissing: return "Введите название машины и её пробег"
        }
    }
}

extension FoundCar {
    /// Данные из макета (node 45854:2936); номер подставляется введённый.
    static func designExample(plate: String) -> FoundCar {
        let parts = PlateFormat.components(plate)
        return FoundCar(
            name: "Mercedes-Benz GL-класс",
            plateLetter: parts?.letter ?? "В",
            plateDigits: parts?.digits ?? "777",
            plateLetters: parts?.letters ?? "ОР",
            plateRegion: parts?.region ?? "777",
            vin: "423423432FRFRIFR",
            generation: "X166 (2015-2026)"
        )
    }
}

#Preview {
    AddCarView()
        .environmentObject(AppState())
}
