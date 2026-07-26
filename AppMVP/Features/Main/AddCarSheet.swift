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
    @Binding var photoItems: [PhotosPickerItem]

    let onClose: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            toolbar

            VStack(spacing: 0) {
                VStack(spacing: 32) {
                    FigmaSegmentedControl(titles: ["По номеру", "По названию"], selection: $tab)

                    if tab == 0 {
                        FigmaTextField(placeholder: "В 777 ОР 777", text: $plate)
                    } else {
                        VStack(spacing: 24) {
                            FigmaGroupedTextField(
                                firstPlaceholder: "Название",
                                first: $name,
                                secondPlaceholder: "Пробег в км",
                                second: $mileage,
                                secondKeyboardType: .numberPad
                            )

                            PhotosPicker(selection: $photoItems, matching: .images) {
                                FigmaRowLabel(systemImage: "photo", title: "Выбрать фото")
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
                .fill(.white)
                .shadow(color: .black.opacity(0.18), radius: 18.75, y: 15)
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
                        .foregroundStyle(Figma.vibrantSecondary)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle()
                                .fill(.white)
                                .overlay(Circle().stroke(Color(white: 232 / 255), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.02), radius: 7.5, y: 8)
                        }
                }
                .accessibilityLabel("Закрыть")

                Spacer()

                Button(action: onSubmit) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color(white: 245 / 255))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Figma.labelsPrimary))
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
