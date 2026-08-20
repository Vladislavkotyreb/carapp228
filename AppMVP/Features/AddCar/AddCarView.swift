import PhotosUI
import SwiftData
import SwiftUI

/// Figma «добавление машины + edge cases» (секция 45854:2880).
/// Один экран с двумя вкладками и состояниями ошибок; координаты из макета
/// (контейнер y = 107.93, высота 735, паддинг 16, кнопка прижата к низу).
struct AddCarView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var metrics: DeviceMetrics

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
    @State private var isSearching = false

    /// Пока поставщика нет — заглушка. Реализация поверх своего сервера
    /// появится вместе с бэкендом, см. docs/BACKEND.md.
    private let lookup: any VehicleLookup = StubVehicleLookup()
    @State private var photo: Image?

    /// Высота контейнера: от координаты макета до нижней safe area.
    /// В макете контейнер 735 упирается в самый низ, и кнопка «Добавить»
    /// заезжает на home indicator.
    private var contentHeight: CGFloat {
        // В макете контейнер 735 от y = 107.93 → низ 842.93, кнопка 54pt
        // прижата к нему, то есть её верх в макете 788.93.
        max(0, metrics.bottomAnchoredY(designY: 788.93, height: 54) + 54 - 107.93)
    }

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

                    // Контрол объявлен один раз, снаружи ветвления: если он
                    // лежит внутри `if tab == 0`, то при переключении SwiftUI
                    // уничтожает вьюху вместе с нажатой кнопкой и её
                    // @Namespace, и переезд пилюли ломается.
                    VStack(spacing: 32) {
                        segmentedControl

                        if tab == 0 { byPlate } else { byName }
                    }
                }

                Spacer(minLength: 0)

                GlassProminentButton(title: "Добавить", isBusy: isSearching, action: submit)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            // В макете контейнер 735 от y = 107.93 упирается в самый низ экрана,
            // и кнопка «Добавить» заезжает на home indicator. Тянем контейнер
            // до нижней границы safe area вместо фиксированной высоты.
            .frame(height: contentHeight, alignment: .top)
            .offset(y: 107.93)

        }
        .ignoresSafeArea()
        // выезд снизу, затемнение кросс-фейдом, свайп вниз — как у остальных шторок
        .bottomSheet(isPresented: Binding(
            get: { foundCar != nil },
            set: { if !$0 { foundCar = nil } }
        )) {
            if let foundCar {
                CarFoundSheet(
                    car: foundCar,
                    onClose: { self.foundCar = nil },
                    onConfirm: { finish() },
                    onReject: {
                        self.foundCar = nil
                        fieldError = .plateNotFound
                    }
                )
                // в макете шторка 390×731 на y = 137.93 → снизу остаётся 5.07
                .padding(.bottom, 5.07)
            }
        }
        // отклик даёт SwiftUI — он уважает системные настройки
        .sensoryFeedback(.error, trigger: shake)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                // Декодирование идёт вне главного актора, см. ImageLoader
                if let uiImage = await ImageLoader.load(item) {
                    photo = Image(uiImage: uiImage)
                }
            }
        }
    }

    // MARK: - Вкладка «По номеру»

    private var byPlate: some View {
        VStack(spacing: 8) {
            FigmaTextField(
                placeholder: "В 777 ОР 777",
                text: $plate,
                placeholderColor: fieldError == nil ? Figma.labelsQuaternary : Figma.labelsTertiary,
                format: PlateFormat.format,
                autocapitalization: .characters,
                submitLabel: .go,
                onSubmit: submit
            )
            .shake(shake)

            if let fieldError {
                caption(fieldError.message, color: Figma.accentsRed)
            }
        }
    }

    // MARK: - Вкладка «По названию»

    private var byName: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                FigmaGroupedTextField(
                    firstPlaceholder: "Название",
                    first: $name,
                    secondPlaceholder: "Пробег в км",
                    second: $mileage,
                    secondKeyboardType: .numberPad,
                    submitLabel: .go,
                    onSubmit: submit
                )
                .shake(shake)
                // 19pt из макета — отступ под капсулой, а не пустота внутри неё
                .padding(.bottom, fieldError == nil ? 19 : 0)

                if let fieldError {
                    caption(fieldError.message, color: Figma.accentsRed)
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
            guard PlateFormat.isValid(plate) else {
                fail(.plateInvalid)
                return
            }
            search()
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

    /// Поиск по номеру. Пока за ним стоит заглушка, но интерфейс уже
    /// асинхронный: у реальных поставщиков ответ приходит не мгновенно,
    /// а у Автокода вообще двумя запросами.
    private func search() {
        guard !isSearching else { return }
        fieldError = nil
        isSearching = true

        Task {
            defer { isSearching = false }
            do {
                let vehicle = try await lookup.lookup(plate: plate)
                foundCar = FoundCar(plate: plate, vehicle: vehicle)
            } catch VehicleLookupError.notFound {
                fail(.plateNotFound)
            } catch {
                fail(.lookupFailed)
            }
        }
    }

    private func finish() {
        // На вкладке «По названию» шторки нет, экран просто закрывается —
        // клавиатуру убираем сами. В ветке ошибки фокус оставляем: там ввод
        // надо исправлять.
        dismissKeyboard()
        modelContext.insert(newCar())
        onFinish?()
    }

    /// Собирает машину из того, что ввёл пользователь. По номеру данные
    /// приходят из «поиска» (пока это макетная заглушка), по названию —
    /// прямо из полей формы.
    private func newCar() -> Car {
        if let foundCar {
            return Car(
                plate: PlateFormat.format(plate),
                name: foundCar.name,
                vin: foundCar.vehicle.displayVIN,
                generation: foundCar.vehicle.generation,
                odometer: foundCar.vehicle.odometer ?? 0
            )
        }
        return Car(
            plate: "",
            name: name.trimmingCharacters(in: .whitespaces),
            odometer: NumberFormat.digits(mileage, or: 0)
        )
    }

    /// Аннотация в макете: «хаптик негативное действие и тряска инпута».
    private func fail(_ error: FieldError) {
        fieldError = error
        withAnimation(.linear(duration: 0.4)) { shake += 1 }
    }
}

// `FieldError` переехал в `Core/Pure/UIState.swift`: он не про вёрстку,
// и на него ссылается каталог состояний.

#Preview {
    AddCarView()
        .modelContainer(for: Car.self, inMemory: true)
}
