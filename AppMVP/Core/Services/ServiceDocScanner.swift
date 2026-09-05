import PDFKit
import UIKit
import Vision

/// Считывание бланка ТО с фото или PDF — целиком на устройстве.
///
/// Фото и сканы идут через Vision OCR (русский + английский, on-device);
/// у цифрового PDF сначала берётся текстовый слой — он точнее и мгновенный,
/// OCR остаётся сканам. Извлечение работ, даты и пробега из текста — чистый
/// `ServiceDocParse`, проверяемый без приложения.
enum ServiceDocScanner {
    /// Сколько страниц PDF читаем: заказ-наряд — одна-две страницы, всё
    /// дальше — регламенты и подписи.
    private static let maxPages = 3

    // MARK: - Фото

    static func parse(image: UIImage) async -> ParsedServiceDoc? {
        guard let cgImage = image.cgImage else { return nil }
        let fragments = await recognize(cgImage)
        guard !fragments.isEmpty else { return nil }
        return ServiceDocParse.parse(fragments)
    }

    // MARK: - PDF

    static func parse(pdfURL url: URL) async -> ParsedServiceDoc? {
        guard let document = PDFDocument(url: url) else { return nil }

        // Текстовый слой: собирается построчно, координаты синтетические —
        // парсеру важен только порядок сверху вниз.
        var lines: [OCRFragment] = []
        for index in 0..<min(document.pageCount, maxPages) {
            guard let text = document.page(at: index)?.string else { continue }
            lines += text.split(whereSeparator: \.isNewline).map { OCRFragment(String($0)) }
        }
        if lines.count >= 4 {
            var y = Double(lines.count)
            let ordered = lines.map { line in
                y -= 1
                return OCRFragment(line.text, minX: 0, midY: y)
            }
            let parsed = ServiceDocParse.parse(ordered)
            if !parsed.works.isEmpty { return parsed }
        }

        // Скан без текстового слоя — рендер страниц и OCR.
        var fragments: [OCRFragment] = []
        for index in 0..<min(document.pageCount, maxPages) {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = min(3, 2000 / max(bounds.width, 1))
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let rendered = page.thumbnail(of: size, for: .mediaBox)
            guard let cgImage = rendered.cgImage else { continue }
            // Страницы складываются в один поток: y второй страницы ниже
            // первой, чтобы ряды не перемешались между страницами.
            let pageFragments = await recognize(cgImage).map {
                OCRFragment($0.text, minX: $0.minX, midY: $0.midY - Double(index))
            }
            fragments += pageFragments
        }
        guard !fragments.isEmpty else { return nil }
        return ServiceDocParse.parse(fragments)
    }

    /// Превью первой страницы PDF — для ленты чеков в форме ТО.
    static func preview(pdfURL url: URL) -> UIImage? {
        guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale = min(2, 1200 / max(bounds.width, 1))
        return page.thumbnail(of: CGSize(width: bounds.width * scale,
                                         height: bounds.height * scale),
                              for: .mediaBox)
    }

    // MARK: - OCR

    /// Распознавание текста с координатами. Vision работает на устройстве,
    /// запись никуда не уходит — та же политика, что у разбора звука.
    private static func recognize(_ cgImage: CGImage) async -> [OCRFragment] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["ru-RU", "en-US"]
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImage)
                guard (try? handler.perform([request])) != nil,
                      let observations = request.results else {
                    return continuation.resume(returning: [])
                }
                let fragments = observations.compactMap { observation -> OCRFragment? in
                    guard let top = observation.topCandidates(1).first else { return nil }
                    return OCRFragment(top.string,
                                       minX: observation.boundingBox.minX,
                                       midY: observation.boundingBox.midY)
                }
                continuation.resume(returning: fragments)
            }
        }
    }
}
