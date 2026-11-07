import AVFoundation
import XCTest
@testable import Beepy

/// Разбор звука на устройстве: проверка доступности не грузит модели, сами
/// модели грузятся и разбирают запись. На iPhone тест заодно меряет, сколько
/// длится загрузка, — ровно столько экран стоял на главном потоке по «Стоп»,
/// пока загрузку не увели в фон (16.10.2026).
final class DiagnosisTests: XCTestCase {
    /// Флаг доступности смотрит только на файлы в бандле. Раньше он поднимал
    /// модели — 58 МБ энкодера — прямо на главном потоке.
    func testAvailabilityCheckIsCheap() {
        let started = Date()
        XCTAssertTrue(LocalDiagnosis.isAvailable)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.05)
    }

    func testModelsLoadAndRecordingIsAnalysed() async throws {
        let started = Date()
        XCTAssertTrue(LocalDiagnosis.load())
        let loadTime = Date().timeIntervalSince(started)
        // В журнал прогона: на iPhone это и есть цена, которую раньше платил
        // главный поток.
        print("Загрузка и прогрев моделей разбора: \(String(format: "%.2f", loadTime)) с")

        let analysed = Date()
        let diagnosis = try await LocalDiagnosis.diagnose(fileURL: try Self.toneRecording())
        print("Разбор после прогрева: \(String(format: "%.2f", Date().timeIntervalSince(analysed))) с")
        // Ровный тон — не мотор: привратник должен это сказать.
        XCTAssertTrue(diagnosis.modelLoaded)
        XCTAssertFalse(diagnosis.verdict.isEmpty)
    }

    /// Три секунды тона 120 Гц с шумом в WAV — как пишет метр.
    private static func toneRecording() throws -> URL {
        let rate = 48_000.0
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tone-\(UUID().uuidString).wav")
        let frames = AVAudioFrameCount(rate * 3)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for i in 0..<Int(frames) {
            samples[i] = Float(0.3 * sin(2 * .pi * 120 * Double(i) / rate) + Double.random(in: -0.02...0.02))
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        return url
    }
}
