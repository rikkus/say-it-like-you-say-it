import Foundation
import AVFoundation
import Speech

/// Everything the real-time audio thread is allowed to touch.
///
/// The tap runs on a high-priority audio thread and must never reach back into
/// the main actor, so it talks only to this box: append the raw samples for the
/// phonetics, convert a copy into the analyser's format, hand that to the
/// analyser's input stream. A lock guards the shared array; the audio thread
/// holds it only long enough to append.
final class AudioBridge: @unchecked Sendable {

    private let lock = NSLock()
    private var storage: [Float] = []
    private var peak: Float = 0

    private let converter: AVAudioConverter?
    private let analyzerFormat: AVAudioFormat?
    private let continuation: AsyncStream<AnalyzerInput>.Continuation

    /// Sample rate of the raw audio kept for phonetic measurement (the mic's own rate).
    let captureRate: Double

    init(micFormat: AVAudioFormat,
         analyzerFormat: AVAudioFormat?,
         continuation: AsyncStream<AnalyzerInput>.Continuation) {
        self.captureRate = micFormat.sampleRate
        self.analyzerFormat = analyzerFormat
        self.continuation = continuation
        if let analyzerFormat, analyzerFormat != micFormat {
            self.converter = AVAudioConverter(from: micFormat, to: analyzerFormat)
        } else {
            self.converter = nil
        }
        storage.reserveCapacity(Int(micFormat.sampleRate) * 60)
    }

    /// Called on the audio thread, once per tap buffer.
    func accept(_ buffer: AVAudioPCMBuffer) {
        appendSamples(from: buffer)
        forwardToAnalyzer(buffer)
    }

    private func appendSamples(from buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var localPeak: Float = 0
        for i in 0..<count { localPeak = max(localPeak, abs(channel[i])) }
        lock.lock()
        storage.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
        peak = localPeak
        lock.unlock()
    }

    private func forwardToAnalyzer(_ buffer: AVAudioPCMBuffer) {
        guard let analyzerFormat else {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }
        guard let converter else {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }
        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard error == nil, status != .error, out.frameLength > 0 else { return }
        continuation.yield(AnalyzerInput(buffer: out))
    }

    // MARK: - read side (main actor)

    /// A snapshot of everything captured so far.
    func snapshot() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func currentPeak() -> Float {
        lock.lock(); defer { lock.unlock() }
        return peak
    }

    func reset() {
        lock.lock(); storage.removeAll(keepingCapacity: true); peak = 0; lock.unlock()
    }
}
