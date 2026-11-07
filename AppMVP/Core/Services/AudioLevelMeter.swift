import AVFoundation
import SwiftUI

/// Громкость с микрофона для живого шара на экране «Ошибки».
///
/// Движок поднимается только на время записи — как гироскоп в `DeviceTilt`:
/// держать вход открытым всё время работы приложения значит без нужды
/// занимать микрофон и жечь батарею.
///
/// Аудиосессия и движок живут на своей очереди, а не на главном потоке.
/// `setActive` — блокирующий вызов (так и сказано в документации Apple), и на
/// iPhone включение и выключение записи подвешивали экран на десятки и сотни
/// миллисекунд прямо в момент нажатия (жалоба «диагностика лагает»,
/// 16.10.2026).
@MainActor
final class AudioLevelMeter: ObservableObject {
    /// Уровень — отдельным объектом. Он меняется на каждом буфере, десятки раз
    /// в секунду; будь он `@Published` здесь, экран, который держит метр,
    /// пересобирался бы целиком с той же частотой. Читают его только шар и
    /// панель — через `LevelReader`.
    let levels = AudioLevel()

    /// Файл последней записи — дописанный, после `stop()`. Тот же тап, что
    /// считает громкость, пишет и звук: поднимать второй микрофонный вход
    /// ради этого нельзя — вход один, и два потребителя дерутся за него.
    @Published private(set) var lastRecording: URL?

    private let capture = Capture()
    private let queue = DispatchQueue(label: "dev.beepy.audio", qos: .userInitiated)
    /// Запись запрошена и не остановлена. Движок поднимается позже, на очереди:
    /// флаг нужен, чтобы быстрый «Стоп» до старта движка его не запустил.
    private var isActive = false

    func start() {
        guard !isActive else { return }
        isActive = true
        levels.begin()

        // Прошлая запись больше никому не нужна — разбор по ней либо уже
        // прошёл, либо не случится. Без чистки файлы копились во временном
        // каталоге до прихода системы: минута звука — около 11 МБ.
        if let old = lastRecording {
            lastRecording = nil
            try? FileManager.default.removeItem(at: old)
        }

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else { self.isActive = false; return }
                guard self.isActive else { return }
                self.queue.async { [capture = self.capture, levels = self.levels] in
                    // Микрофон занят другим приложением или сессия не
                    // поднялась — шар в этом случае просто дышит сам по себе.
                    try? capture.start { value in
                        Task { @MainActor in levels.ingest(value) }
                    }
                }
            }
        }
    }

    /// Остановить запись. Возвращает файл, когда он дописан: заголовок WAV
    /// дописывается при освобождении файла, и разбор раньше этого получил бы
    /// обрезанную запись. Ждать можно — ждёт фоновая очередь, а не экран.
    @discardableResult
    func stop() async -> URL? {
        guard isActive else { return nil }
        isActive = false
        levels.end()
        let url = await withCheckedContinuation { continuation in
            queue.async { [capture] in continuation.resume(returning: capture.stop()) }
        }
        lastRecording = url
        return url
    }

    /// RMS буфера в шкалу 0…1. Считается вне главного актора — тап приходит
    /// на своей очереди, и держать там что-то тяжёлое нельзя.
    nonisolated static func normalizedLevel(of buffer: AVAudioPCMBuffer,
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

/// Уровень громкости 0…1 — то, что меняется на каждом буфере.
@MainActor
final class AudioLevel: ObservableObject {
    @Published private(set) var level: Double = 0
    /// Идёт запись — буферы принимаются.
    private var accepting = false
    /// Уровень фона. Стартует высоко и опускается к настоящей тишине за
    /// первые секунды: начни он с нуля, первые вдохи шара были бы ложными.
    private var noiseFloor: Double = 0.5

    fileprivate func begin() { accepting = true }

    fileprivate func end() {
        accepting = false
        noiseFloor = 0.5
        withAnimation(.easeOut(duration: 0.4)) { level = 0 }
    }

    fileprivate func ingest(_ value: Double) {
        // Буфер, пришедший после «Стоп», шар не трогает.
        guard accepting else { return }
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
}

/// Читает уровень и пересобирает только своё содержимое — шар или панель, —
/// а не весь экран, который держит метр.
struct LevelReader<Content: View>: View {
    @ObservedObject var levels: AudioLevel
    @ViewBuilder let content: (Double) -> Content

    init(_ levels: AudioLevel, @ViewBuilder content: @escaping (Double) -> Content) {
        self.levels = levels
        self.content = content
    }

    var body: some View { content(levels.level) }
}

/// Движок и пишущий файл. Трогается только на очереди метра — отсюда
/// `@unchecked Sendable`: порядок доступа держит последовательная очередь.
private final class Capture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var url: URL?
    private var isRunning = false

    func start(onLevel: @escaping @Sendable (Double) -> Void) throws {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // Пишем в WAV, а не в m4a: сервер разбора читает файл через
        // soundfile, а тот берёт PCM без ffmpeg.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-\(UUID().uuidString).wav")
        // Файл держит только замыкание тапа: снятие тапа его освобождает, и
        // заголовок WAV дописывается ровно в `stop()`.
        let file = try? AVAudioFile(forWriting: url, settings: format.settings)
        self.url = file == nil ? nil : url

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            // Запись идёт прямо в очереди тапа: перекладывать буферы на
            // другой поток нельзя, движок переиспользует их память.
            try? file?.write(from: buffer)
            guard let value = AudioLevelMeter.normalizedLevel(of: buffer, floor: -50) else { return }
            onLevel(value)
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.url = nil
            try? session.setActive(false)
            throw error
        }
        isRunning = true
    }

    /// Возвращает дописанный файл записи.
    func stop() -> URL? {
        guard isRunning else { return nil }
        isRunning = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        defer { url = nil }
        return url
    }
}
