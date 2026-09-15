// Вырезка машины из сгенерированного кадра: Vision, macOS 14+.
//
// Зачем. `compose_hero()` кладёт под машину единый синтетический пол и
// тень, и для этого ему нужна машина без собственного отражения из
// сырья. Без вырезки отражение считается частью машины, после прижатия
// к чёрному оно ложится поверх синтетического пола чёрной полосой, и
// колёса тонут в ней. Ровно это вышло у первой партии 2026-09-15.
//
// Порог по яркости здесь не работает: шины тёмные, как и отражение, и
// любой порог, убирающий отражение, откусывает колёса. Vision разделяет
// их семантически. Так были собраны 76 кадров прода, но тот скрипт жил
// во временном каталоге сессии — этот его замена.
//
// Сборка (один раз, потом бинарник быстрый):
//     swiftc -O tools/cutout.swift -o ~/canary-catalog/cutout
// Запуск, парами вход/выход:
//     ~/canary-catalog/cutout in.png out.png [in2.png out2.png …]
// Код возврата 1, если хоть один кадр не вырезался; генератор это ловит.

import AppKit
import CoreImage
import Foundation
import Vision

let args = CommandLine.arguments
guard args.count >= 3, (args.count - 1) % 2 == 0 else {
    FileHandle.standardError.write(Data("usage: cutout in.png out.png [in out …]\n".utf8))
    exit(64)
}

let context = CIContext()
var failed = 0

for i in stride(from: 1, to: args.count - 1, by: 2) {
    let input = URL(fileURLWithPath: args[i])
    let output = URL(fileURLWithPath: args[i + 1])

    guard let image = CIImage(contentsOf: input) else {
        print("не читается: \(args[i])"); failed += 1; continue
    }

    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(ciImage: image, options: [:])
    do {
        try handler.perform([request])
    } catch {
        print("vision: \(error.localizedDescription) — \(args[i])"); failed += 1; continue
    }
    guard let observation = request.results?.first else {
        print("передний план не найден: \(args[i])"); failed += 1; continue
    }

    let maskBuffer: CVPixelBuffer
    do {
        maskBuffer = try observation.generateScaledMaskForImage(
            forInstances: observation.allInstances, from: handler)
    } catch {
        print("маска: \(error.localizedDescription) — \(args[i])"); failed += 1; continue
    }

    // Маска — один канал 0…1 в размере кадра. Машина поверх чёрного:
    // всё, что Vision не считает передним планом, гаснет в ноль — в том
    // числе отражение и пол из сырья.
    let mask = CIImage(cvPixelBuffer: maskBuffer)
    let black = CIImage(color: CIColor.black).cropped(to: image.extent)
    let cut = image.applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: black,
        kCIInputMaskImageKey: mask,
    ])

    guard let cg = context.createCGImage(cut, from: image.extent) else {
        print("рендер: \(args[i])"); failed += 1; continue
    }
    let bitmap = NSBitmapImageRep(cgImage: cg)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        print("png: \(args[i])"); failed += 1; continue
    }
    do {
        try png.write(to: output)
        print("ок: \(args[i + 1])")
    } catch {
        print("запись: \(error.localizedDescription) — \(args[i + 1])"); failed += 1
    }
}

print("ошибок: \(failed)")
exit(failed == 0 ? 0 : 1)
