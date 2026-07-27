import PhotosUI
import SwiftUI

struct ServiceWork: Identifiable {
    let id = UUID()
    var title = ""
    var amount = ""
}

/// Figma «добавление то» (node 45870:2868 → Sheet 45882:5275), Detent = Large.
/// Кнопка «+» добавляет ещё пару полей — состояние «добавление то много сущностей».
struct AddServiceSheet: View {
    /// «Добавление ТО» или «Изменение ТО» — шторка одна на оба случая.
    var title = "Добавление ТО"
    @Binding var date: Date
    @Binding var mileage: String
    @Binding var works: [ServiceWork]
    @Binding var photoItems: [PhotosPickerItem]
    @Binding var photos: [UIImage]

    let onClose: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            toolbar

            VStack(spacing: 32) {
                // Дата + Пробег
                VStack(spacing: 0) {
                    HStack {
                        Text("Дата")
                            .font(.system(size: 17))
                            .tracking(-0.43)
                            .foregroundStyle(Figma.labelsPrimary)

                        Spacer()

                        DatePicker("", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)

                    separator

                    fieldRow("Пробег", text: $mileage, keyboard: .numberPad)
                }
                .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: 26))

                // Работы
                VStack(alignment: .trailing, spacing: 20) {
                    Text("Работы")
                        .font(.system(size: 22, weight: .bold))
                        .figmaLineHeight(28, fontSize: 22, weight: .bold)
                        .foregroundStyle(Figma.labelsPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // «добавление то много сущностей»: у каждой группы своя корзина,
                    // у последней — ещё и «+». Когда группа одна, корзины нет.
                    VStack(alignment: .trailing, spacing: 12) {
                        ForEach(Array($works.enumerated()), id: \.element.id) { index, $work in
                            VStack(alignment: .trailing, spacing: 12) {
                                VStack(spacing: 0) {
                                    fieldRow("Название ", text: $work.title)
                                    separator
                                    fieldRow("Сумма", text: $work.amount, keyboard: .numberPad)
                                }
                                .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: 26))

                                HStack(spacing: 12) {
                                    if works.count > 1 {
                                        circleButton("trash", label: "Удалить работу") { works.remove(at: index) }
                                    }
                                    if index == works.count - 1 {
                                        circleButton("plus", label: "Добавить работу") { works.append(ServiceWork()) }
                                    }
                                }
                            }
                        }
                    }
                }

                // Figma «добавление то» с фото (45885:3449): превью 98.842×94 radius 16
                // с кружком-крестиком, ниже — строка «Добавить фото».
                VStack(spacing: 0) {
                    if !photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(photos.indices, id: \.self) { index in
                                    Image(uiImage: photos[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 98.842, height: 94)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(alignment: .topTrailing) {
                                            Button { photos.remove(at: index) } label: {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 8.57))
                                                    .foregroundStyle(Figma.labelsPrimary)
                                                    .frame(width: 16, height: 16)
                                                    .background(Figma.fillsTertiary, in: Circle())
                                                    .frame(width: 44, height: 44)
                                                    .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Удалить фото")
                                        }
                                }
                            }
                        }
                        .frame(height: 94)
                        .padding(16)

                        separator
                    }

                    PhotosPicker(selection: $photoItems, matching: .images) {
                        FigmaRowLabel(systemImage: "photo", title: "Добавить фото")
                    }
                }
                .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: 26))
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
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

    /// Визуально 34pt как в макете, но область нажатия расширена до 44pt по HIG.
    private func circleButton(_ symbol: String, label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Figma.labelsPrimary)
                .frame(width: 34, height: 34)
                .background(Figma.fillsTertiary, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var separator: some View {
        Rectangle()
            .fill(Figma.separatorsVibrant)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private func fieldRow(_ placeholder: String, text: Binding<String>,
                          keyboard: UIKeyboardType = .default) -> some View {
        ZStack(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 17, weight: .medium))
                    .tracking(-0.43)
                    .foregroundStyle(Figma.labelsTertiary)
            }
            TextField("", text: text)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Figma.labelsPrimary)
                .keyboardType(keyboard)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var toolbar: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.43)
                .foregroundStyle(Figma.vibrantControlsPrimary)

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Figma.vibrantSecondary)
                        .frame(width: 44, height: 44)
                        // Кромку круглой кнопки даёт системное стекло
                        .liquidGlass(in: Circle()) {
                            Circle()
                                .fill(.white)
                                .overlay(Circle().stroke(Color(white: 232 / 255), lineWidth: 0.5))
                        }
                        .motionRim(in: Circle())
                        .shadow(color: .black.opacity(0.02), radius: 7.5, y: 8)
                }
                .accessibilityLabel("Закрыть")

                Spacer()

                Button(action: onSave) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color(white: 245 / 255))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Figma.labelsPrimary))
                }
            }
        }
        .buttonStyle(.plain)
        .frame(height: 44)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}
