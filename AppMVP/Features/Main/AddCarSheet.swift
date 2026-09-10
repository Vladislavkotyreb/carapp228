import PhotosUI
import SwiftUI

/// Figma «главная_добавить новую по номеру» (45974:5159) → Sheet 45974:5188, Detent = Large.
/// Открывается по «Добавить авто» с карусели. Тулбар: крестик слева, заголовок,
/// чёрная галочка справа; поля сверху, «Добавить» прижата к низу.
struct AddCarSheet: View {
    @Binding var tab: Int
    @Binding var plate: String
    @Binding var name: String
    @Binding var mileage: String
    /// Цена — необязательная: её знает не каждый, а число из ниоткуда на
    /// главной хуже прочерка.
    @Binding var price: String
    @Binding var photoItems: [PhotosPickerItem]
    /// Выбранный снимок. Раньше форма его не показывала вовсе — о чём и был
    /// пункт «нет самого фото».
    var photo: UIImage?

    let onClose: () -> Void
    let onSubmit: () -> Void

    /// Тряска полей на пустую отправку: кнопки не гасим (пользователь просил
    /// не дизейбл, а отклик), но вслепую форму не отправляем — поле трясётся
    /// и телефон отдаёт ошибку.
    @State private var shake: CGFloat = 0

    var body: some View {
        VStack(spacing: 16) {
            toolbar

            VStack(spacing: 0) {
                VStack(spacing: 32) {
                    FigmaSegmentedControl(titles: ["По номеру", "По названию"], selection: $tab)

                    if tab == 0 {
                        // Номерная рамка вместо обычного поля (просьба
                        // пользователя). Откат — вернуть FigmaTextField:
                        // `git revert` коммита с PlateInputField.
                        PlateInputField(text: $plate, onSubmit: submit)
                            .shake(shake)
                    } else {
                        VStack(spacing: 24) {
                            // Три строки одной капсулой: цена отдельным
                            // полем читалась чужой и красилась иначе
                            // (замечание пользователя). В макете 45854:2880
                            // цены нет вовсе — она наша добавка.
                            FigmaGroupedTextField(
                                firstPlaceholder: "Название",
                                first: $name,
                                secondPlaceholder: "Пробег в км",
                                second: $mileage,
                                secondKeyboardType: .numberPad,
                                secondFormat: NumberFormat.groupedInput,
                                thirdPlaceholder: "Цена авто, ₽",
                                third: $price,
                                thirdKeyboardType: .numberPad,
                                thirdFormat: NumberFormat.groupedInput,
                                submitLabel: .go,
                                onSubmit: submit
                            )
                            .shake(shake)

                            if let photo {
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 160)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 26))
                                    // scaledToFill вылезает за рамку и
                                    // хит-зоной: портретный снимок накрывал
                                    // поля выше и съедал их тапы.
                                    .allowsHitTesting(false)
                            }

                            // Одно фото на машину: без ограничения галерея
                            // предлагала мультивыбор, а брали мы первый
                            // снимок (замечание пользователя).
                            PhotosPicker(selection: $photoItems,
                                         maxSelectionCount: 1,
                                         selectionBehavior: .default,
                                         matching: .images) {
                                FigmaRowLabel(systemImage: "photo",
                                              title: photo == nil ? "Выбрать фото" : "Заменить фото")
                            }
                        }
                    }
                }

                // Кнопка стоит сразу под полями с отступом 32 (просьба
                // пользователя), а не прижата к низу шторки: рядом с
                // формой она читается частью формы.
                Spacer(minLength: 0).frame(height: 32)

                GlassProminentButton(title: "Добавить", action: submit)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38)
                .fill(Figma.sheetBackground)
                .shadow(color: .black.opacity(0.18), radius: 18.75, y: 15)
                // Системный фон шторки отключён через .presentationBackground(.clear),
                // поэтому подложку надо самим дотянуть до низа экрана — иначе
                // в нижней safe area просвечивает тёмный экран под шторкой.
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(Figma.vibrantPrimary)
                .frame(width: 58, height: 4)
                .padding(.top, 5)
        }
        // Шторка живёт в системном .sheet — панель клавиатуры с экрана под
        // ней сюда не доезжает, нужна своя.
        .sensoryFeedback(.error, trigger: shake)
        .keyboardDismissBar()
        // Кнопка «Добавить» остаётся на месте, а не прыгает на клавиатуру:
        // просьба пользователя. Клавиатура её просто накрывает.
        .ignoresSafeArea(.keyboard)
    }

    /// Отправка с проверкой: по номеру нужен валидный номер, по названию —
    /// непустое имя. Иначе тряска и ошибка-хаптик вместо тихого «ничего».
    private func submit() {
        let filled = tab == 0
            ? PlateFormat.isValid(plate)
            : !name.trimmingCharacters(in: .whitespaces).isEmpty
        guard filled else {
            withAnimation(.linear(duration: 0.4)) { shake += 1 }
            return
        }
        onSubmit()
    }

    private var toolbar: some View {
        ZStack {
            Text("Добавление авто")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.43)
                .foregroundStyle(Figma.vibrantControlsPrimary)

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        // Кромку круглой кнопки даёт системное стекло
                        .liquidGlass(in: Circle(), tint: Figma.sheetControl) {
                            Circle()
                                .fill(Figma.sheetControl)
                                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                        }
                        .contentShape(Circle())
                        .motionRim(in: Circle())
                        .shadow(color: .black.opacity(0.02), radius: 7.5, y: 8)
                }
                .accessibilityLabel("Закрыть")

                Spacer()

                // Белая галочка вместо синей из прототипа: акцент кнопок белый.
                Button(action: submit) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Figma.labelsPrimary))
                        .contentShape(Circle())
                }
                .accessibilityLabel("Добавить авто")
            }
        }
        .buttonStyle(.plain)
        .frame(height: 44)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}
