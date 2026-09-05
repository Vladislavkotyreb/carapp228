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
    /// Уровень фона. Стартует высоко и опускается к настоящей тишине за
    /// первые секунды: начни он с нуля, первые вдохи шара были бы ложными.
    private var noiseFloor: Double = 0.5

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
        noiseFloor = 0.5
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

            // Прошлая запись больше никому не нужна — разбор по ней либо уже
            // прошёл, либо не случится. Без чистки файлы копились во временном
            // каталоге до прихода системы: минута звука — около 11 МБ.
            if let old = lastRecording {
                lastRecording = nil
                try? FileManager.default.removeItem(at: old)
            }

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
        // Считаем **превышение над фоном**, а не абсолютную громкость.
        //
        // Абсолютная шкала и была причиной того, что шар не реагировал на
        // звук. Замер в обычной комнате: фон даёт 0.40–0.56, речь 0.68–0.74 —
        // то есть фон съедает половину шкалы, и после усиления оба упираются
        // в потолок. Разницы на экране нет никакой.
        //
        // Фон отслеживается сам: вниз идёт быстро (стало тише — это новый
        // фон), вверх ползёт еле-еле (громкий звук не должен становиться
        // фоном за секунду). Побочная польза — шар одинаково работает и в
        // тихой комнате, и в гараже под работающим мотором.
        // Вверх — очень медленно, около тридцати секунд на подъём. Быстрее
        // нельзя: мотор звучит ровно, и за десять секунд записи он целиком
        // ушёл бы в фон, а шар снова замер бы.
        noiseFloor += (value - noiseFloor) * (value < noiseFloor ? 0.2 : 0.0006)
        let excess = max(0, value - noiseFloor)
        // Превышение на 0.35 считаем полным размахом. При 0.25 речь мгновенно
        // упиралась в потолок, и градаций между «тихо» и «громко» не
        // оставалось вовсе — шар только моргал между нулём и максимумом.
        let target = min(1, excess / 0.35)

        // Вверх реагируем быстро, вниз отпускаем плавнее — но не настолько,
        // как раньше. Отпускание 0.12 гасило шар сильнее любых правок
        // отрисовки: лента не успевала опасть между звуками.
        let rate = target > level ? 0.6 : 0.3
        level += (target - level) * rate
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
