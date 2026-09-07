import Foundation
import AVFoundation
import Speech
import CoreMedia
import Observation

/// A word the transcriber recognised, with where it sits in the recording.
struct TimedWord: Sendable, Identifiable {
    let id = UUID()
    var text: String
    var start: Double
    var end: Double
    var normalised: String { TimedWord.normalise(text) }

    static func normalise(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0 == "'" }
    }
}

/// One microphone feeding two consumers at once: a live transcriber and a raw
/// sample buffer. This is the whole reason for going native — on the web, iOS
/// gives the microphone to one or the other, never both.
@MainActor
@Observable
final class SpeechEngine {

    enum Phase: Equatable {
        case idle
        case preparing(String)
        case unavailable(String)
        case ready
        case listening
        case working
    }

    private(set) var phase: Phase = .idle
    /// Text already committed by the recogniser.
    private(set) var settledText: String = ""
    /// Text still being revised as you speak — shown dimmed.
    private(set) var volatileText: String = ""
    /// Every settled word with its time range.
    private(set) var words: [TimedWord] = []
    /// 0…1 microphone level, for the meter.
    private(set) var level: Float = 0

    var transcript: String {
        (settledText + " " + volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let audioEngine = AVAudioEngine()
    private var bridge: AudioBridge?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?

    private(set) var captureRate: Double = 48_000

    // MARK: - permissions and model

    func prepare() async {
        phase = .preparing("Asking permission…")

        let micOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        guard micOK else {
            phase = .unavailable("Without the microphone there is nothing to measure. You can turn it back on in Settings.")
            return
        }

        guard SpeechTranscriber.isAvailable else {
            phase = .unavailable("Speech recognition isn't available on this device.")
            return
        }

        phase = .preparing("Finding a voice model…")
        var chosen = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
        if chosen == nil {
            chosen = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_GB"))
        }
        guard let locale = chosen else {
            phase = .unavailable("No speech model for your language.")
            return
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        let installed = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
        if !installed.contains(locale.identifier(.bcp47)) {
            phase = .preparing("Downloading the voice model — this happens once…")
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
            } catch {
                phase = .unavailable("The voice model wouldn't download. Check the network and try again.")
                return
            }
        }

        self.transcriber = transcriber
        phase = .ready
    }

    // MARK: - listening

    func startListening() async throws {
        guard case .ready = phase else { return }
        guard let transcriber else { return }

        settledText = ""
        volatileText = ""
        words = []

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.continuation = continuation

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = audioEngine.inputNode
        let micFormat = input.outputFormat(forBus: 0)
        captureRate = micFormat.sampleRate

        let bridge = AudioBridge(micFormat: micFormat,
                                 analyzerFormat: analyzerFormat,
                                 continuation: continuation)
        self.bridge = bridge

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
            bridge.accept(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        try await analyzer.start(inputSequence: stream)

        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    await self.consume(result)
                }
            } catch {
                // the stream ends when we finish; nothing to report
            }
        }

        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                guard let self, let bridge = self.bridge else { return }
                self.level = min(1, bridge.currentPeak() * 6)
            }
        }

        phase = .listening
    }

    private func consume(_ result: SpeechTranscriber.Result) {
        let attributed = result.text
        if result.isFinal {
            volatileText = ""
            let plain = String(attributed.characters)
            settledText += (settledText.isEmpty ? "" : " ") + plain.trimmingCharacters(in: .whitespaces)
            for run in attributed.runs {
                guard let range = run.audioTimeRange else { continue }
                let text = String(attributed[run.range].characters).trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                words.append(TimedWord(text: text,
                                       start: range.start.seconds,
                                       end: (range.start + range.duration).seconds))
            }
        } else {
            volatileText = String(attributed.characters)
        }
    }

    /// Stop the microphone and let the recogniser flush whatever is outstanding.
    @discardableResult
    func stopListening() async -> Recording {
        guard phase == .listening else {
            return Recording(samples: bridge?.snapshot() ?? [], rate: captureRate, words: words)
        }
        phase = .working

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        continuation?.finish()

        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        // let the last results land
        try? await Task.sleep(for: .milliseconds(450))

        meterTask?.cancel(); meterTask = nil
        resultsTask?.cancel(); resultsTask = nil
        level = 0

        let samples = bridge?.snapshot() ?? []
        let recording = Recording(samples: samples, rate: captureRate, words: words)

        analyzer = nil
        continuation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        phase = .ready
        return recording
    }

    func discard() {
        bridge?.reset()
        settledText = ""
        volatileText = ""
        words = []
    }
}

/// What one spoken passage leaves behind: the audio, and where each word sits in it.
struct Recording: Sendable {
    var samples: [Float]
    var rate: Double
    var words: [TimedWord]

    var duration: Double { rate > 0 ? Double(samples.count) / rate : 0 }
    var spokeAtAll: Bool { !words.isEmpty && samples.count > Int(rate * 0.2) }

    /// Sample range for a word, padded, clamped to what was actually recorded.
    func range(for word: TimedWord, pad: Double = 0.06) -> Range<Int>? {
        let from = Int(max(0, word.start - pad) * rate)
        let to = Int(min(duration, word.end + pad) * rate)
        guard from < to, to <= samples.count, to - from > Int(rate * 0.03) else { return nil }
        return from..<to
    }

    /// Find a spoken word by text. Falls back to a prefix match so "pyjamas"
    /// still matches when the recogniser writes "pajamas".
    func find(_ target: String) -> TimedWord? {
        let want = TimedWord.normalise(target)
        guard !want.isEmpty else { return nil }
        if let exact = words.last(where: { $0.normalised == want }) { return exact }
        if let prefix = words.last(where: {
            let w = $0.normalised
            guard w.count >= 4, want.count >= 4 else { return false }
            return w.hasPrefix(want.prefix(4)) && abs(w.count - want.count) <= 3
        }) { return prefix }
        return nil
    }
}
