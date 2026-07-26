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

    var body: some View {
        VStack(spacing: 16) {
            toolbar

            VStack(spacing: 0) {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        Text(car.name)
                            .font(.system(size: 26, weight: .bold))
                            .figmaLineHeight(31.2, fontSize: 26, weight: .bold)
                            .foregroundStyle(Figma.labelsPrimary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        plate
                    }

                    // Фото авто: в макете слой-заглушка без изображения
                    // (аннотация: «простая генерация машины или парсинг студийных фото»).
                    RoundedRectangle(cornerRadius: 26)
                        .fill(Figma.fillsTertiary)
                        .frame(height: 240)

                    // Строки рисуются только при наличии данных: поставщик
                    // может не отдать VIN или прислать его замаскированным.
                    VStack(alignment: .leading, spacing: 16) {
                        if let vin = car.vehicle.displayVIN {
                            specLine("VIN: ", vin)
                        }
                        if let generation = car.vehicle.generation {
                            specLine("Поколение: ", generation)
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
        // в макете это стеклянная поверхность (Fill + Shadow + слой Glass Effect).
        // Тонировать не нужно: экран добавления авто под шторкой светлый,
        // так стекло ближе к макету.
        .liquidGlass(in: Self.shape) { Self.shape.fill(.white) }
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
                        .foregroundStyle(Figma.vibrantSecondary)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle()
                                .fill(.white)
                                .overlay(Circle().stroke(Figma.separatorsVibrant, lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.02), radius: 7.5, y: 8)
                        }
                }
                .accessibilityLabel("Закрыть")

                Spacer()

                Button(action: onConfirm) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Figma.labelsPrimary))
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

    private var plate: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(car.plateLetter)
                Text(car.plateDigits)
                Text(car.plateLetters)
            }

            Rectangle()
                .fill(Figma.separatorsVibrant)
                .frame(width: 1, height: 20.117)

            Text(car.plateRegion)
        }
        .font(.system(size: 17, weight: .semibold))
        .tracking(-0.43)
        .foregroundStyle(Figma.labelsPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 32)
        .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: 12))
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
