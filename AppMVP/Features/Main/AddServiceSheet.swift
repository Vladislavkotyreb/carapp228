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

    /// Двухтактное удаление: первый тап взводит кнопку (красная, «Удалить»),
    /// второй удаляет. Взведена одна на всю форму; таймер сбрасывает.
    @State private var armedTrash: UUID?
    @State private var disarmTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            toolbar

            // Прокрутка обязательна: с распарсенным документом работ
            // становится много, и без неё низ формы недостижим, а верх
            // наезжает на тулбар (баг с телефона).
            ScrollView(showsIndicators: false) {
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

                    fieldRow("Пробег", text: $mileage, keyboard: .numberPad,
                             format: NumberFormat.groupedInput)
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
                                    fieldRow("Сумма", text: $work.amount, keyboard: .numberPad,
                                             format: NumberFormat.groupedInput)
                                }
                                .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: 26))

                                HStack(spacing: 12) {
                                    if works.count > 1 {
                                        trashButton(for: work.id) {
                                            works.remove(at: index)
                                        }
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
                                        // Хит-зона scaledToFill шире рамки —
                                        // вылезшие поля крали тапы у крестиков
                                        // соседних превью. Кнопка ниже в
                                        // overlay и не гаснет.
                                        .allowsHitTesting(false)
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
            .padding(.bottom, 24)
            }
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38)
                .fill(Figma.sheetBackground)
                .shadow(color: .black.opacity(0.18), radius: 18.75, y: 15)
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(Figma.vibrantPrimary)
                .frame(width: 58, height: 4)
                .padding(.top, 5)
        }
    }

    /// Корзина в два такта — просьба пользователя: случайный тап не должен
    /// сносить заполненную работу. Первый тап взводит (красная капсула с
    /// «Удалить», хаптик), второй — удаляет; три секунды без второго тапа
    /// или тап по другой корзине снимают взвод.
    private func trashButton(for id: UUID,
                             delete: @escaping () -> Void) -> some View {
        let armed = armedTrash == id
        return Button {
            if armed {
                armedTrash = nil
                disarmTask?.cancel()
                delete()
            } else {
                armedTrash = id
                disarmTask?.cancel()
                disarmTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    armedTrash = nil
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 15))
                if armed {
                    Text("Удалить")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundStyle(armed ? .white : Figma.accentsRed)
            .padding(.horizontal, armed ? 14 : 0)
            .frame(minWidth: 34)
            .frame(height: 34)
            .background(armed ? Figma.accentsRed : Figma.fillsTertiary,
                        in: Capsule())
            .frame(height: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // Простой easeOut вместо пружины: спружиненная смена ширины капсулы
        // внутри перестраиваемого ряда лагала на устройстве.
        .animation(.easeOut(duration: 0.18), value: armed)
        .sensoryFeedback(.warning, trigger: armed) { _, isArmed in isArmed }
        .accessibilityLabel(armed ? "Подтвердить удаление работы"
                                  : "Удалить работу")
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
            .fill(Figma.separatorsOnDark)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private func fieldRow(_ placeholder: String, text: Binding<String>,
                          keyboard: UIKeyboardType = .default,
                          format: ((String) -> String)? = nil) -> some View {
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
                .onChange(of: text.wrappedValue) { _, new in
                    guard let format else { return }
                    let masked = format(new)
                    // переписываем только при отличии, иначе будет цикл
                    if masked != new { text.wrappedValue = masked }
                }
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
                Button(action: onSave) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Figma.labelsPrimary))
                        .contentShape(Circle())
                }
            }
        }
        .buttonStyle(.plain)
        .frame(height: 44)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}
