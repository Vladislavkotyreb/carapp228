import ImageIO
import PhotosUI
import SwiftUI
import UIKit

/// Загрузка снимков из галереи.
///
/// Декодирование вынесено с главного актора намеренно: `Task { }` внутри
/// вьюхи наследует MainActor, и `UIImage(data:)` на полноразмерном кадре
/// с 48-мегапиксельной камеры вешает интерфейс на секунды. Заодно кадр
/// уменьшается до размера отображения — полноразмерные `UIImage` в памяти
/// приводили к выгрузке приложения по jetsam.
enum ImageLoader {
    /// Максимальная сторона результата в пикселях. 1200 хватает и на фото
    /// машины во всю ширину экрана, и на чек ТО.
    static let maxPixelSize = 1200

    /// Один снимок.
    static func load(_ item: PhotosPickerItem) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return await downsample(data)
    }

    /// Несколько снимков конкурентно, с сохранением порядка выбора.
    static func load(_ items: [PhotosPickerItem]) async -> [UIImage] {
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask { (index, await load(item)) }
            }

            var result: [Int: UIImage] = [:]
            for await (index, image) in group {
                if let image { result[index] = image }
            }
            return result.sorted { $0.key < $1.key }.map(\.value)
        }
    }

    /// Восстановление сохранённых чеков. Через тот же `downsample`: он читает
    /// уменьшенный кадр, не разворачивая в память полноразмерный битмап, и
    /// работает вне главного актора.
    static func decode(_ blobs: [Data]) async -> [UIImage] {
        var result: [UIImage] = []
        for blob in blobs {
            if let image = await downsample(blob) { result.append(image) }
        }
        return result
    }

    /// Кодирование для хранения. Качество 0.8 — чек остаётся читаемым, а вес
    /// кадра 1200px держится в пределах пары сотен килобайт.
    ///
    /// Синхронно и на главном акторе намеренно: сюда приходят уже уменьшенные
    /// кадры, JPEG на таком размере занимает единицы миллисекунд. Тормозило
    /// когда-то не кодирование, а разбор полноразмерных снимков с камеры.
    static func encode(_ images: [UIImage]) -> [Data] {
        images.compactMap { $0.jpegData(compressionQuality: 0.8) }
    }

    /// Уменьшение через ImageIO: он читает уменьшенный кадр сразу, не разворачивая
    /// в память полноразмерный битмап.
    private static func downsample(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source, 0, options as CFDictionary
            ) else { return nil }

            return UIImage(cgImage: cgImage)
        }.value
    }
}
