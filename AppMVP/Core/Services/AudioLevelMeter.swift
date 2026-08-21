import AVFoundation
import SwiftUI

/// Громкость с микрофона для живого шара на экране «Ошибки».
///
/// Движок поднимается только на время записи — как гироскоп в `DeviceTilt`:
/// держать вход открытым всё время работы приложения значит без нужды
/// занимать микрофон и жечь батарею.
@MainActor
final class AudioLevelMeter: ObservableObject {
    /// Сглаженный уровень 0…1. Сглаживание нужно, иначе шар дёргается на
    /// каждом буфере: RMS скачет даже на ровном звуке.
    @Published private(set) var level: Double = 0

    /// Файл последней записи. Тот же самый тап, что считает громкость, пишет
    /// и звук: поднимать второй микрофонный вход ради этого нельзя — вход
    /// один, и два потребителя дерутся за него.
    @Published private(set) var lastRecording: URL?

    private let engine = AVAudioEngine()
    private var isRunning = false
    /// Пишущий файл держится до `stop()`: `AVAudioFile` дописывает заголовок
    /// WAV при освобождении, и пока ссылка жива, файл читать нельзя.
    private var writer: AVAudioFile?

    /// Ниже этого порога в децибелах считаем тишиной. −50 дБ примерно
    /// соответствует тихой комнате, всё что тише — шум самого микрофона.
    private let silenceFloor: Double = -50

    func start() {
        guard !isRunning else { return }

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard granted else { return }
                self?.run()
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Освобождаем файл до того, как отдать ссылку наружу: заголовок WAV
        // дописывается здесь, и без этого читатель получит обрезанный файл.
        writer = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        withAnimation(.easeOut(duration: 0.4)) { level = 0 }
    }

    private func run() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)

            // Пишем в WAV, а не в m4a: сервер разбора читает файл через
            // soundfile, а тот берёт PCM без ffmpeg. С m4a пришлось бы тащить
            // ffmpeg на сервер ради ничего.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("engine-\(UUID().uuidString).wav")
            let file = try? AVAudioFile(forWriting: url, settings: format.settings)
            writer = file
            lastRecording = file == nil ? nil : url

            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                // Запись идёт прямо в очереди тапа: перекладывать буферы на
                // другой поток нельзя, движок переиспользует их память.
                try? file?.write(from: buffer)
                guard let value = Self.normalizedLevel(of: buffer, floor: -50) else { return }
                Task { @MainActor in self?.apply(value) }
            }

            try engine.start()
            isRunning = true
        } catch {
            // Микрофон занят другим приложением или сессия не поднялась —
            // шар в этом случае просто дышит сам по себе.
            isRunning = false
        }
    }

    private func apply(_ value: Double) {
        // Вверх реагируем быстро, вниз отпускаем плавнее — но не настолько,
        // как раньше. Отпускание 0.12 гасило шар сильнее любых правок
        // отрисовки: лента не успевала опасть между звуками и держалась на
        // одной толщине, из-за чего живая запись выглядела мертвее тишины.
        let rate = value > level ? 0.6 : 0.3
        level += (value - level) * rate
    }

    /// RMS буфера в шкалу 0…1. Считается вне главного актора — тап приходит
    /// на своей очереди, и держать там что-то тяжёлое нельзя.
    private nonisolated static func normalizedLevel(of buffer: AVAudioPCMBuffer,
                                                    floor: Double) -> Double? {
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return nil }

        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }

        let rms = sqrt(Double(sum) / Double(count))
        guard rms > 0 else { return 0 }

        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels - floor) / -floor))
    }
}
