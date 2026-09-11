import SwiftUI

/// Figma «добавление авто по номеру данные введены и апи поиска запущен» → Sheet (node 45854:2936).
/// Карточка 390×731 на x = 6, y = 137.93; скругления сверху 34, снизу 58.
struct CarFoundSheet: View {
    private static let shape = UnevenRoundedRectangle(
        topLeadingRadius: 34, bottomLeadingRadius: 58,
        bottomTrailingRadius: 58, topTrailingRadius: 34
    )

    let car: FoundCar
    let onClose: () -> Void
    let onConfirm: () -> Void
    let onReject: () -> Void

    /// Кадр каталога для найденной модели — грузится один раз при создании
    /// шторки, а не в body: декод HEIC на каждую пересборку ни к чему.
    private let preview: UIImage?
    /// Средний цвет краёв кадра: им зона превью растекается за рамку мягким
    /// свечением — карточка «утопает» в шторке (идея пользователя, приём
    /// подложки обложек в Apple Music).
    private let previewAmbient: Color

    init(car: FoundCar, onClose: @escaping () -> Void,
         onConfirm: @escaping () -> Void, onReject: @escaping () -> Void) {
        self.car = car
        self.onClose = onClose
        self.onConfirm = onConfirm
        self.onReject = onReject
        let plate = car.plateLetter + car.plateDigits + car.plateLetters
            + car.plateRegion
        if let slug = CarCatalog.slug(name: car.vehicle.name,
                                      generation: car.vehicle.generation,
                                      plate: plate),
           let url = Bundle.main.url(forResource: slug, withExtension: "heic",
                                     subdirectory: "CarCatalog") {
            preview = UIImage(contentsOfFile: url.path)
        } else {
            // Модели нет в каталоге — «машина под покрывалом» тем же путём,
            // что каталожный кадр: одна ветка, один амбиент-эффект.
            preview = UIImage(named: "CarPhoto")
        }
        previewAmbient = preview.map(Self.edgeAverageColor) ?? .black
    }

    /// Средний цвет рамки картинки: уменьшаем до 12×12 и усредняем периметр —
    /// дёшево и достаточно для подложки.
    private static func edgeAverageColor(of image: UIImage) -> Color {
        let side = 12
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let small = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side), format: format
        ).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let cg = small.cgImage, let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return .black }
        let bpr = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
        var r = 0, g = 0, b = 0, n = 0
        for y in 0..<side {
            for x in 0..<side where x == 0 || y == 0 || x == side - 1 || y == side - 1 {
                let i = y * bpr + x * bpp
                r += Int(bytes[i]); g += Int(bytes[i + 1]); b += Int(bytes[i + 2])
                n += 1
            }
        }
        guard n > 0 else { return .black }
        return Color(red: Double(r) / Double(n) / 255,
                     green: Double(g) / Double(n) / 255,
                     blue: Double(b) / Double(n) / 255)
    }

    var body: some View {
        VStack(spacing: 16) {
            toolbar

            VStack(spacing: 0) {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        Text(car.name)
                            .font(.system(size: 26, weight: .bold))
                            .figmaLineHeight(31.2, fontSize: 26, weight: .bold)
                            .foregroundStyle(Figma.titleGradient)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        plate
                    }

                    // Фото авто. Аннотация макета: «простая генерация машины
                    // или парсинг студийных фото» — ровно это и показываем:
                    // кадр каталога, подобранный по найденной модели (и по
                    // номеру — пасхалки). Не нашёлся — заглушка, как в макете.
                    if let preview {
                        // Безрамочно (просьба пользователя): кадр без
                        // карточки, машина стоит прямо в шторке — швы
                        // прячет размытая подложка фона тем же кадром.
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 240)
                            .allowsHitTesting(false)
                    } else {
                        RoundedRectangle(cornerRadius: 26)
                            .fill(Figma.fillsTertiary)
                            .frame(height: 240)
                    }

                    // Строки рисуются только при наличии данных: поставщик
                    // может не отдать VIN или прислать его замаскированным.
                    VStack(alignment: .leading, spacing: 16) {
                        if let vin = car.vehicle.displayVIN {
                            specLine("VIN: ", vin)
                        }
                        if let generation = car.vehicle.generation {
                            specLine("Поколение: ", generation)
                        }
                        if let year = car.vehicle.year {
                            specLine("Год выпуска: ", String(year))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    GlassProminentButton(title: "Да, добавить", action: onConfirm)
                    GlassButton(title: "Это не моя машина", color: Figma.labelsPrimary, action: onReject)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(height: 645)
        }
        .padding(.top, 16)
        .frame(width: 390, height: 731, alignment: .top)
        // Тёмная тема: поверхность шторки — Backgrounds (Grouped)/Secondary,
        // как у тёмных шторок ноды 46225:7443. Тонируем: без тона стекло
        // над чёрным экраном уходило бы в непредсказуемый серый.
        // Безрамочность по макету 45854:2921: шторка ЗАЛИВАЕТСЯ цветом фона
        // кадра (средний цвет его рамки) — граница картинки исчезает, машина
        // стоит прямо в шторке. Никаких блюров: ровная заливка.
        .liquidGlass(in: Self.shape, tint: previewAmbient) {
            Self.shape.fill(previewAmbient)
        }
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .overlay(alignment: .top) {
            Capsule()
                .fill(Figma.grabber)
                .frame(width: 58, height: 4)
                .padding(.top, 5)
        }
    }

    // MARK: - Toolbar - Top - iPhone

    private var toolbar: some View {
        ZStack {
            Text("Это ваш автомобиль?")
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

                // Белая галочка-акцент: в тёмном прототипе она синяя, но акцент
                // кнопок оставлен белым по прямому указанию пользователя.
                Button(action: onConfirm) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Figma.labelsPrimary))
                        .contentShape(Circle())
                }
                .accessibilityLabel("Это мой автомобиль")
            }
        }
        .buttonStyle(.plain)
        .frame(height: 44)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Госномер

    /// Компактная плашка, как на главной (нода 45854:2921): узкий SF,
    /// серый текст на тёмной подложке — а не крупный номер строкой.
    private var plate: some View {
        HStack(spacing: 3.5) {
            HStack(spacing: 3.5) {
                Text(car.plateLetter)
                Text(car.plateDigits)
                Text(car.plateLetters)
            }

            Rectangle()
                .fill(Figma.separatorsVibrant)
                .frame(width: 0.875, height: 17.603)
                .blendMode(.softLight)

            Text(car.plateRegion)
        }
        .font(.system(size: 14, weight: .semibold).width(.condensed))
        .tracking(-0.4)
        .foregroundStyle(Figma.graysGray2)
        .padding(.horizontal, 10.5)
        .padding(.vertical, 3.5)
        .frame(height: 28)
        .background(Figma.fillsPrimary, in: RoundedRectangle(cornerRadius: 10.5))
    }

    private func specLine(_ label: String, _ value: String) -> some View {
        (Text(label).foregroundColor(Figma.graysGray) + Text(value).foregroundColor(Figma.labelsPrimary))
            .font(.system(size: 17))
            .tracking(-0.43)
    }
}

struct FoundCar {
    let plateLetter: String
    let plateDigits: String
    let plateLetters: String
    let plateRegion: String
    /// Данные от поставщика: марка с моделью, VIN, поколение, пробег.
    let vehicle: FoundVehicle
}

extension FoundCar {
    var name: String { vehicle.name }

    /// Собирает карточку из введённого номера и ответа поставщика.
    init(plate: String, vehicle: FoundVehicle) {
        let parts = PlateFormat.components(plate)
        self.init(
            plateLetter: parts?.letter ?? "",
            plateDigits: parts?.digits ?? "",
            plateLetters: parts?.letters ?? "",
            plateRegion: parts?.region ?? "",
            vehicle: vehicle
        )
    }
}

/// Кадр каталога по набранному названию — превью в формах добавления машины.
///
/// Вью общее на два экрана: онбординг (`AddCarView`) и шторку с главной
/// (`AddCarSheet`). До сих пор превью показывал только поиск по номеру, через
/// «Это ваш автомобиль?»; по названию человек добавлял машину вслепую и видел
/// её кадр уже на главной.
///
/// **Показывать его или нет, решает вызывающий** — `CarCatalog.slug(name:)`
/// не `nil`. Это чистая проверка без диска, и она нужна снаружи: пустое вью
/// внутри `VStack` всё равно получает отступы соседей, и незнакомая машина
/// оставляла бы в форме дыру в высоту `spacing`.
struct CarCatalogPreview: View {
    /// Что напечатано в поле «Название».
    let name: String
    /// Высота блока: в онбординге под превью отведено 200, в шторке — 160.
    var height: CGFloat = 200

    @State private var image: UIImage?

    /// Слаг считается из названия прямо здесь: функция чистая, диска и сети
    /// не трогает. На диск ходит только `load()` и только на смену слага —
    /// «Лада Веста» и «лада веста 2019» дают один и тот же кадр.
    private var slug: String? { CarCatalog.slug(name: name) }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Подложка держит высоту, пока кадр декодируется: без неё
                // блок возникал бы из ничего и толкал форму вниз.
                RoundedRectangle(cornerRadius: 26)
                    .fill(Figma.fillsQuaternary.opacity(0.12))

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 26))
            // Обязательно: `scaledToFill` вылезает за рамку не только
            // отрисовкой, но и хит-зоной — `clipShape` режет пиксели, а тапы
            // нет, и широкий кадр накрыл бы поля ввода выше.
            .allowsHitTesting(false)

            // Подпись не украшение: кадр студийный и белый, и без оговорки
            // его принимают за фотографию своей машины.
            Text("Кадр из каталога — ваше фото его заменит")
                .font(.system(size: 12))
                .figmaLineHeight(16, fontSize: 12)
                .foregroundStyle(Figma.labelsTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(Motion.selection, value: image == nil)
        .task(id: slug) { await load() }
    }

    private func load() async {
        guard let slug,
              let url = Bundle.main.url(forResource: slug, withExtension: "heic",
                                        subdirectory: "CarCatalog"),
              let data = try? Data(contentsOf: url) else {
            image = nil
            return
        }
        // Через `ImageLoader`, а не `UIImage(contentsOfFile:)`: тот отдаёт кадр
        // с отложенным декодированием, и разворачивается он потом на главном
        // акторе — ровно в тот момент, когда человек печатает.
        image = await ImageLoader.decode([data]).first
    }
}
