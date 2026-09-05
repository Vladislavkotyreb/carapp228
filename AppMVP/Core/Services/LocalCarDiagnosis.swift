import AVFoundation
import CoreML
import Foundation

/// Локальный разбор звука двигателя: тот же пайплайн, что на сервере
/// `tools/diagnosis_server.py`, целиком на устройстве. Аудио-башня CLAP
/// сконвертирована в Core ML (`tools/clap_to_coreml.py`), линейные головы и
/// текстовые эмбеддинги промптов привратника лежат в `DiagnosisSupport.json`.
///
/// Паритет с сервером доказан сквозной сверкой на demo.wav
/// (`tools/clap_parity_e2e.py`): привратник |Δ| = 0.0002, головы сходятся до
/// третьего знака. Два места, где поведение отличается сознательно:
/// - запись длиннее 10 с сервер режет для привратника **случайным** кропом,
///   здесь берутся первые 10 с — детерминированное подмножество того же;
/// - каскад изоляции кусков (Silero VAD) не портирован: локальный путь всегда
///   идёт фолбэком «окна всего файла» — ровно тем, которым сервер фактически
///   шёл на всех замеренных телефонных записях (у всех segments == 0).
///
/// Мел-фронтенд и энкодер — две модели не случайно: у power-спектра
/// динамический диапазон ~200 дБ, и fp16 жмёт его с обеих сторон, поэтому
/// фронтенд остаётся в fp32, а трансформеру хватает половинной точности.
enum LocalDiagnosis {
    static let sampleRate = 48_000.0
    /// Вход энкодера фиксированный: 10 с при 48 кГц.
    static let windowSamples = 480_000

    // MARK: - Ресурсы

    /// Сайдкар конверсии: промпты, текстовые эмбеддинги, головы, пороги.
    struct Support: Decodable {
        struct Head: Decodable {
            let classes: [String]
            let coef: [[Double]]
            let intercept: [Double]
            let temperature: Double
            let scalerMean: [Double]?
            let scalerScale: [Double]?

            enum CodingKeys: String, CodingKey {
                case classes, coef, intercept, temperature
                case scalerMean = "scaler_mean"
                case scalerScale = "scaler_scale"
            }
        }

        let prompts: [String]
        let promptCodes: [String]
        let engineIndex: Int
        let engineThreshold: Double
        let logitScaleA: Double
        let textEmbeddings: [[Double]]
        let heads: [String: Head]
        let faultHi: Double
        let faultLo: Double

        enum CodingKeys: String, CodingKey {
            case prompts
            case promptCodes = "prompt_codes"
            case engineIndex = "engine_index"
            case engineThreshold = "engine_threshold"
            case logitScaleA = "logit_scale_a"
            case textEmbeddings = "text_embeddings"
            case heads
            case faultHi = "fault_hi"
            case faultLo = "fault_lo"
        }
    }

    private final class Models: @unchecked Sendable {
        let mel: MLModel
        let encoder: MLModel
        let support: Support

        init?() {
            guard let melURL = Bundle.main.url(forResource: "ClapMelFrontend",
                                               withExtension: "mlmodelc"),
                  let encURL = Bundle.main.url(forResource: "ClapAudioEncoder",
                                               withExtension: "mlmodelc"),
                  let jsonURL = Bundle.main.url(forResource: "DiagnosisSupport",
                                                withExtension: "json"),
                  let data = try? Data(contentsOf: jsonURL),
                  let support = try? JSONDecoder().decode(Support.self, from: data)
            else { return nil }

            let config = MLModelConfiguration()
            config.computeUnits = .all
            guard let mel = try? MLModel(contentsOf: melURL, configuration: config),
                  let encoder = try? MLModel(contentsOf: encURL, configuration: config)
            else { return nil }

            self.mel = mel
            self.encoder = encoder
            self.support = support
        }
    }

    /// Модели поднимаются первым разбором и живут до конца процесса —
    /// как `_lazy()` на сервере.
    private static let models = Models()

    static var isAvailable: Bool { models != nil }

    // MARK: - Разбор

    static func diagnose(fileURL: URL) async throws -> Diagnosis {
        guard let m = models else { throw DiagnosisError.notConfigured }
        let audio = try loadAudio(fileURL)
        guard !audio.isEmpty else { throw DiagnosisError.server("не удалось прочитать звук") }

        // Привратник — по записи целиком, с нулевым паддингом: `Clap.score`
        // зовёт процессор с padding=True, и все его пороги сняты именно так.
        let gateVector = try embed(zeroPadded(audio), with: m)
        let scores = gateScores(gateVector, support: m.support)
        let engineP = scores[m.support.engineIndex]
        let heardIndex = scores.indices.max(by: { scores[$0] < scores[$1] }) ?? 0
        let heard = Diagnosis.HeardKind(rawValue: m.support.promptCodes[heardIndex]) ?? .unknown

        guard engineP >= m.support.engineThreshold else {
            return Diagnosis(verdict: "uncertain", faultProbability: 0,
                             engineKnockProbability: 0, regions: [], causes: [],
                             note: "", isEngine: false,
                             engineProbability: rounded3(engineP), heard: heard)
        }

        // Окна файла — фолбэк `_window_vectors` сервера: до трёх окон по 10 с,
        // почти тихие и короче полсекунды пропускаются. Куски для голов
        // паддятся повтором (`Clap.embed`, дефолт repeatpad).
        var vectors: [[Double]] = []
        for span in windows(of: audio) {
            vectors.append(try embed(repeatPadded(span), with: m))
        }
        if vectors.isEmpty {
            return Diagnosis(verdict: "uncertain", faultProbability: 0,
                             engineKnockProbability: 0, regions: [], causes: [],
                             note: "clip is too short or has no usable (non-silent) audio to diagnose.",
                             isEngine: true, engineProbability: rounded3(engineP), heard: heard)
        }

        // Головы — повтор `Classifier.diagnose`: вероятности каждого окна
        // усредняются, эмбеддинги не смешиваются никогда.
        let kind = headProbabilities(m.support.heads["kind"], over: vectors)
        let pFault = kind["fault"] ?? 0
        let verdict = pFault >= m.support.faultHi ? "fault"
                    : pFault <= m.support.faultLo ? "normal" : "uncertain"

        let knock = headProbabilities(m.support.heads["knock"], over: vectors)
        let pKnock = knock["knock"] ?? 0

        // Зона: общая голова, при вероятном стуке мягко подмешивается
        // специалист по стукам — вес равен p(knock), как на сервере.
        var regionProbs = headProbabilities(m.support.heads["region"], over: vectors)
        if pKnock > 0, let specialist = m.support.heads["knock_region"] {
            let knockRegion = headProbabilities(specialist, over: vectors)
            var blended: [String: Double] = [:]
            for zone in Set(regionProbs.keys).union(knockRegion.keys) {
                blended[zone] = (1 - pKnock) * (regionProbs[zone] ?? 0)
                              + pKnock * (knockRegion[zone] ?? 0)
            }
            regionProbs = blended
        }
        let sentinels: Set<String> = ["unknown", "none", "nan", ""]
        let regions = regionProbs.sorted { $0.value > $1.value }.prefix(3)
            .filter { !sentinels.contains($0.key.lowercased()) }
            .map { Diagnosis.Region(zone: $0.key, p: rounded3($0.value)) }

        let cause = headProbabilities(m.support.heads["cause"], over: vectors)
        let causes = cause.sorted { $0.value > $1.value }.prefix(3)
            .map { Diagnosis.Cause(part: $0.key, p: rounded3($0.value), note: "") }

        return Diagnosis(
            verdict: verdict,
            faultProbability: pFault,
            engineKnockProbability: pKnock,
            regions: Array(regions),
            causes: Array(causes),
            note: "Cleaning isolated no clear mechanical sound; diagnosed the whole clip. "
                + "Fine cause from sound alone is uncertain; treat as triage, not a final diagnosis.",
            isEngine: true,
            engineProbability: rounded3(engineP),
            heard: heard
        )
    }

    // MARK: - Аудио

    /// Читает файл и приводит к 48 кГц моно float32 — как `librosa.load` на
    /// сервере. Ресемплер здесь системный (AVAudioConverter), у librosa свой:
    /// на записях с другой частотой числа могут разойтись в мелочах, но
    /// микрофон iPhone и так пишет 48 кГц.
    private static func loadAudio(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames)
        else { return [] }
        try file.read(into: inBuffer)

        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: sampleRate,
                                            channels: 1, interleaved: false)
        else { return [] }

        if inFormat.sampleRate == sampleRate, inFormat.channelCount == 1,
           inFormat.commonFormat == .pcmFormatFloat32,
           let data = inBuffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: data[0],
                                             count: Int(inBuffer.frameLength)))
        }

        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else { return [] }
        let capacity = AVAudioFrameCount(
            Double(inBuffer.frameLength) * sampleRate / inFormat.sampleRate + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat,
                                               frameCapacity: capacity) else { return [] }

        var fed = false
        var conversionError: NSError?
        converter.convert(to: outBuffer, error: &conversionError) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return inBuffer
        }
        guard conversionError == nil, let data = outBuffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(outBuffer.frameLength)))
    }

    /// Паддинг привратника: нули справа, длинное — первые 10 с.
    private static func zeroPadded(_ audio: [Float]) -> [Float] {
        if audio.count >= windowSamples { return Array(audio.prefix(windowSamples)) }
        return audio + [Float](repeating: 0, count: windowSamples - audio.count)
    }

    /// Паддинг кусков для голов — repeatpad из ClapFeatureExtractor:
    /// целое число повторов, остаток нулями.
    private static func repeatPadded(_ audio: [Float]) -> [Float] {
        if audio.count >= windowSamples { return Array(audio.prefix(windowSamples)) }
        let repeats = windowSamples / audio.count
        var result = [Float]()
        result.reserveCapacity(windowSamples)
        for _ in 0..<repeats { result.append(contentsOf: audio) }
        result.append(contentsOf: [Float](repeating: 0, count: windowSamples - result.count))
        return result
    }

    /// Окна `_window_vectors`: вся запись, если она короче 10 с, иначе до трёх
    /// окон — начало, середина, конец. Почти тихие окна выбрасываются: CLAP
    /// кладёт тишину рядом с кластером неисправностей.
    private static func windows(of audio: [Float]) -> [[Float]] {
        let sr = Int(sampleRate)
        let offsets: [Int]
        if audio.count <= windowSamples {
            offsets = [0]
        } else {
            let last = audio.count - windowSamples
            offsets = [0, last / 2, last]
        }
        var spans: [[Float]] = []
        for offset in offsets {
            let span = Array(audio[offset..<min(offset + windowSamples, audio.count)])
            guard span.count >= sr / 2 else { continue }
            guard span.contains(where: { abs($0) >= 1e-3 }) else { continue }
            spans.append(span)
        }
        return spans
    }

    // MARK: - Модели

    /// Волна ровно в 480000 сэмплов → L2-нормированный вектор 512.
    private static func embed(_ samples: [Float], with m: Models) throws -> [Double] {
        let wave = try MLMultiArray(shape: [1, NSNumber(value: windowSamples)],
                                    dataType: .float32)
        samples.withUnsafeBufferPointer { source in
            wave.dataPointer.withMemoryRebound(to: Float.self, capacity: windowSamples) {
                $0.update(from: source.baseAddress!, count: windowSamples)
            }
        }

        let melOut = try m.mel.prediction(
            from: MLDictionaryFeatureProvider(dictionary: ["waveform": wave]))
        guard let melArray = melOut.featureValue(for: "mel")?.multiArrayValue else {
            throw DiagnosisError.server("мел-фронтенд не вернул спектрограмму")
        }

        let encOut = try m.encoder.prediction(
            from: MLDictionaryFeatureProvider(dictionary: ["mel": melArray]))
        guard let emb = encOut.featureValue(for: "embedding")?.multiArrayValue else {
            throw DiagnosisError.server("энкодер не вернул эмбеддинг")
        }

        var vector = (0..<emb.count).map { emb[$0].doubleValue }
        let norm = (vector.reduce(0) { $0 + $1 * $1 }).squareRoot() + 1e-9
        for i in vector.indices { vector[i] /= norm }
        return vector
    }

    /// Доли промптов привратника: softmax(logit_scale · cos) — формула
    /// `logits_per_audio` из ClapModel, сверена с сервером на demo.wav.
    private static func gateScores(_ vector: [Double], support: Support) -> [Double] {
        let logits = support.textEmbeddings.map { text in
            support.logitScaleA * zip(text, vector).reduce(0) { $0 + $1.0 * $1.1 }
        }
        let peak = logits.max() ?? 0
        let exps = logits.map { exp($0 - peak) }
        let total = exps.reduce(0, +)
        return exps.map { $0 / total }
    }

    /// Вероятности одной головы, усреднённые по окнам, — повтор `_proba`:
    /// скалирование, логиты, температура, сигмоида или софтмакс, пулинг.
    /// У бинарных голов sklearn логит принадлежит **второму** классу
    /// (`classes_[1]`), первому достаётся дополнение.
    private static func headProbabilities(_ head: Support.Head?,
                                          over vectors: [[Double]]) -> [String: Double] {
        guard let head else { return [:] }
        let dim = vectors[0].count
        let mean = head.scalerMean ?? [Double](repeating: 0, count: dim)
        let scale = head.scalerScale ?? [Double](repeating: 1, count: dim)
        let T = head.temperature > 0 ? head.temperature : 1

        var pooled = [Double](repeating: 0, count: head.classes.count)
        for vector in vectors {
            let z = (0..<dim).map { (vector[$0] - mean[$0]) / scale[$0] }
            let logits = zip(head.coef, head.intercept).map { row, bias in
                bias + zip(row, z).reduce(0) { $0 + $1.0 * $1.1 }
            }
            let probs: [Double]
            if logits.count == 1 {
                let p1 = 1 / (1 + exp(-logits[0] / T))
                probs = [1 - p1, p1]
            } else {
                let peak = logits.map { $0 / T }.max() ?? 0
                let exps = logits.map { exp($0 / T - peak) }
                let total = exps.reduce(0, +)
                probs = exps.map { $0 / total }
            }
            for i in pooled.indices { pooled[i] += probs[i] }
        }
        for i in pooled.indices { pooled[i] /= Double(vectors.count) }
        return Dictionary(uniqueKeysWithValues: zip(head.classes, pooled))
    }

    private static func rounded3(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }
}
