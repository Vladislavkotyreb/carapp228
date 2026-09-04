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

    var body: some View {
        VStack(spacing: 16) {
            toolbar

            VStack(spacing: 0) {
                VStack(spacing: 32) {
                    FigmaSegmentedControl(titles: ["По номеру", "По названию"], selection: $tab)

                    if tab == 0 {
                        FigmaTextField(
                            placeholder: "В 777 ОР 777",
                            text: $plate,
                            format: PlateFormat.format,
                            autocapitalization: .characters,
                            submitLabel: .go,
                            onSubmit: onSubmit
                        )
                    } else {
                        VStack(spacing: 24) {
                            FigmaGroupedTextField(
                                firstPlaceholder: "Название",
                                first: $name,
                                secondPlaceholder: "Пробег в км",
                                second: $mileage,
                                secondKeyboardType: .numberPad,
                                submitLabel: .go,
                                onSubmit: onSubmit
                            )

                            // Отдельным полем, а не третьей строкой капсулы:
                            // та объявлена ровно на две строки и 105pt.
                            FigmaTextField(placeholder: "Цена авто, ₽",
                                           text: $price,
                                           keyboardType: .numberPad)

                            if let photo {
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 160)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 26))
                            }

                            PhotosPicker(selection: $photoItems, matching: .images) {
                                FigmaRowLabel(systemImage: "photo",
                                              title: photo == nil ? "Выбрать фото" : "Заменить фото")
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                GlassProminentButton(title: "Добавить", action: onSubmit)
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
                Button(action: onSubmit) {
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
