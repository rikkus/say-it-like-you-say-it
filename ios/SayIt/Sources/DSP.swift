import Foundation
import Accelerate

/// Phonetic measurement over raw PCM. Pure functions, no audio-session state:
/// everything here takes a slice of samples and a sample rate and returns numbers.
enum DSP {

    // MARK: - windows and spectra

    /// Magnitude spectrum of a frame, Hamming-windowed, zero-padded to a power of two.
    static func magnitudeSpectrum(_ frame: ArraySlice<Float>) -> [Float] {
        let n = frame.count
        guard n > 8 else { return [] }
        var size = 1
        while size < n { size <<= 1 }
        let log2n = vDSP_Length(log2(Double(size)).rounded())
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        var windowed = [Float](repeating: 0, count: size)
        var window = [Float](repeating: 0, count: n)
        vDSP_hamm_window(&window, vDSP_Length(n), 0)
        let base = frame.startIndex
        for i in 0..<n { windowed[i] = frame[base + i] * window[i] }

        var real = windowed
        var imag = [Float](repeating: 0, count: size)
        var magnitudes = [Float](repeating: 0, count: size / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(size / 2))
            }
        }
        return magnitudes
    }

    // MARK: - envelopes and segmentation

    struct Envelope {
        var values: [Float]
        var hop: Int
    }

    static func rmsEnvelope(_ x: [Float], rate: Double, windowMs: Double = 20, hopMs: Double = 5) -> Envelope {
        let w = max(1, Int(rate * windowMs / 1000))
        let h = max(1, Int(rate * hopMs / 1000))
        guard x.count >= w else { return Envelope(values: [], hop: h) }
        var out: [Float] = []
        out.reserveCapacity((x.count - w) / h + 1)
        var i = 0
        while i + w <= x.count {
            var mean: Float = 0
            x.withUnsafeBufferPointer { p in
                vDSP_measqv(p.baseAddress! + i, 1, &mean, vDSP_Length(w))
            }
            out.append(sqrt(mean))
            i += h
        }
        return Envelope(values: out, hop: h)
    }

    static func smooth(_ a: [Float], radius: Int) -> [Float] {
        guard radius > 0, !a.isEmpty else { return a }
        var out = [Float](repeating: 0, count: a.count)
        for i in 0..<a.count {
            let lo = max(0, i - radius), hi = min(a.count - 1, i + radius)
            var s: Float = 0
            for j in lo...hi { s += a[j] }
            out[i] = s / Float(hi - lo + 1)
        }
        return out
    }

    /// Contiguous energetic stretches separated by at least `gapMs` of quiet.
    static func segmentRegions(_ x: [Float], rate: Double,
                               gapMs: Double = 170, floorRatio: Float = 0.10,
                               minMs: Double = 90) -> [Range<Int>] {
        let env = rmsEnvelope(x, rate: rate)
        guard !env.values.isEmpty else { return [] }
        let sm = smooth(env.values, radius: 2)
        let peak = sm.max() ?? 0
        let noise = percentile(sm, 0.12)
        let threshold = max(noise * 2.6, peak * floorRatio, 1e-4)
        let gapFrames = Int(gapMs / 5), minFrames = Int(minMs / 5)

        var regions: [Range<Int>] = []
        var start = -1, quiet = 0
        for i in 0..<sm.count {
            if sm[i] > threshold {
                if start < 0 { start = i }
                quiet = 0
            } else if start >= 0 {
                quiet += 1
                if quiet >= gapFrames {
                    let end = i - quiet
                    if end - start >= minFrames {
                        regions.append((start * env.hop)..<min(x.count, (end + 1) * env.hop))
                    }
                    start = -1; quiet = 0
                }
            }
        }
        if start >= 0, sm.count - start >= minFrames {
            regions.append((start * env.hop)..<x.count)
        }
        return regions
    }

    static func percentile(_ a: [Float], _ p: Double) -> Float {
        guard !a.isEmpty else { return 0 }
        let sorted = a.sorted()
        return sorted[min(sorted.count - 1, max(0, Int(p * Double(sorted.count - 1))))]
    }

    // MARK: - syllable nuclei

    struct Nucleus {
        var centre: Int
        var level: Float
        var normalised: Float
    }

    /// Peaks in the 250–1100 Hz band energy: one per syllable, near enough.
    static func syllableNuclei(_ x: [Float], rate: Double, range: Range<Int>) -> [Nucleus] {
        let w = max(8, Int(rate * 0.025)), h = max(1, Int(rate * 0.008))
        var band: [Float] = []
        var positions: [Int] = []
        var i = range.lowerBound
        while i + w <= range.upperBound {
            let mag = magnitudeSpectrum(x[i..<(i + w)])
            if mag.isEmpty { i += h; continue }
            let df = rate / Double(mag.count * 2)
            var acc: Float = 0
            let lo = Int(250 / df), hi = min(mag.count - 1, Int(1100 / df))
            if lo <= hi { for k in lo...hi { acc += mag[k] * mag[k] } }
            band.append(sqrt(acc))
            positions.append(i)
            i += h
        }
        guard !band.isEmpty else { return [] }
        let v = smooth(band, radius: 2)
        guard let mx = v.max(), mx > 0 else { return [] }
        let threshold = mx * 0.30
        let minGap = max(1, Int(95.0 / 8.0))

        var peaks: [(index: Int, value: Float)] = []
        for i in 1..<(v.count - 1) {
            guard v[i] >= v[i - 1], v[i] > v[i + 1], v[i] > threshold else { continue }
            if let last = peaks.last {
                if i - last.index < minGap {
                    if v[i] > last.value { peaks[peaks.count - 1] = (i, v[i]) }
                    continue
                }
                let dip = v[last.index...i].min() ?? 0
                if dip > 0.62 * min(v[i], last.value) {
                    if v[i] > last.value { peaks[peaks.count - 1] = (i, v[i]) }
                    continue
                }
            }
            peaks.append((i, v[i]))
        }
        return peaks.map { Nucleus(centre: positions[$0.index], level: $0.value, normalised: $0.value / mx) }
    }

    // MARK: - formants

    /// Decimate towards ~11 kHz so a low-order LPC fit covers F1–F3 and no more.
    static func decimate(_ x: [Float], rate: Double, target: Double = 11025) -> (samples: [Float], rate: Double) {
        let factor = max(1, Int((rate / target).rounded()))
        guard factor > 1 else { return (x, rate) }
        let taps = 33
        let fc = 0.5 / Double(factor)
        var h = [Double](repeating: 0, count: taps)
        var sum = 0.0
        for i in 0..<taps {
            let m = Double(i) - Double(taps - 1) / 2
            let sinc = m == 0 ? 2 * fc : sin(2 * .pi * fc * m) / (.pi * m)
            let win = 0.54 - 0.46 * cos(2 * .pi * Double(i) / Double(taps - 1))
            h[i] = sinc * win
            sum += h[i]
        }
        for i in 0..<taps { h[i] /= sum }

        let outCount = x.count / factor
        var out = [Float](repeating: 0, count: outCount)
        for n in 0..<outCount {
            let centre = n * factor
            var acc = 0.0
            for k in 0..<taps {
                let idx = centre + k - (taps - 1) / 2
                if idx >= 0 && idx < x.count { acc += h[k] * Double(x[idx]) }
            }
            out[n] = Float(acc)
        }
        return (out, rate / Double(factor))
    }

    /// Autocorrelation LPC via Levinson–Durbin.
    static func lpc(_ frame: [Double], order: Int) -> [Double]? {
        let n = frame.count
        guard n > order + 1 else { return nil }
        var r = [Double](repeating: 0, count: order + 1)
        for k in 0...order {
            var s = 0.0
            for i in 0..<(n - k) { s += frame[i] * frame[i + k] }
            r[k] = s
        }
        guard r[0] > 0 else { return nil }
        r[0] = r[0] * 1.0001 + 1e-9

        var a = [Double](repeating: 0, count: order + 1)
        a[0] = 1
        var err = r[0]
        for i in 1...order {
            var acc = r[i]
            for j in 1..<i { acc += a[j] * r[i - j] }
            let k = -acc / err
            let old = a
            if i > 1 { for j in 1..<i { a[j] = old[j] + k * old[i - j] } }
            a[i] = k
            err *= (1 - k * k)
            if err <= 0 { return nil }
        }
        return a
    }

    /// Peak-pick the LPC envelope — steadier than root-solving on short frames.
    static func formants(frame: [Float], rate: Double, order: Int) -> [Double] {
        guard frame.count > order + 2 else { return [] }
        var pre = [Double](repeating: 0, count: frame.count)
        for i in 1..<frame.count { pre[i] = Double(frame[i]) - 0.97 * Double(frame[i - 1]) }
        for i in 0..<pre.count {
            pre[i] *= 0.54 - 0.46 * cos(2 * .pi * Double(i) / Double(pre.count - 1))
        }
        guard let a = lpc(pre, order: order) else { return [] }

        let steps = 700
        let fmax = min(5000.0, rate / 2)
        var envelope = [Double](repeating: 0, count: steps)
        for i in 0..<steps {
            let f = Double(i + 1) * fmax / Double(steps)
            let w = 2 * .pi * f / rate
            var re = 0.0, im = 0.0
            for k in 0..<a.count {
                re += a[k] * cos(-w * Double(k))
                im += a[k] * sin(-w * Double(k))
            }
            envelope[i] = 1 / max(1e-12, (re * re + im * im).squareRoot())
        }

        var found: [Double] = []
        for i in 1..<(steps - 1) where envelope[i] > envelope[i - 1] && envelope[i] >= envelope[i + 1] {
            let f = Double(i + 1) * fmax / Double(steps)
            if f < 180 { continue }
            if let last = found.last, f < last + 120 { continue }
            found.append(f)
            if found.count >= 4 { break }
        }
        return found
    }

    struct VowelMeasurement {
        var f1: Double
        var f2: Double
        var frames: Int
        var earlyF1: Double
        var earlyF2: Double
        var lateF1: Double
        var lateF2: Double
        /// How far the vowel travels between its first and last third — a diphthong detector.
        var glide: Double {
            hypot((lateF1 - earlyF1) / 120, (lateF2 - earlyF2) / 220)
        }
    }

    /// Median F1/F2 across the steady middle of a region, plus its trajectory.
    static func vowel(_ x: [Float], rate: Double, range: Range<Int>) -> VowelMeasurement? {
        guard range.count > Int(rate * 0.03) else { return nil }
        let slice = Array(x[range])
        let (d, dRate) = decimate(slice, rate: rate)
        guard d.count > Int(dRate * 0.03) else { return nil }

        let from = Int(Double(d.count) * 0.28)
        let to = Int(Double(d.count) * 0.78)
        let win = max(16, Int(dRate * 0.030))
        let hop = max(1, Int(dRate * 0.010))
        let order = min(16, 2 + Int(dRate / 1000))

        var f1s: [Double] = [], f2s: [Double] = []
        var i = from
        while i + win <= to {
            let f = formants(frame: Array(d[i..<(i + win)]), rate: dRate, order: order)
            if f.count >= 2, f[0] > 170, f[0] < 1150, f[1] > f[0] + 150, f[1] < 3300 {
                f1s.append(f[0]); f2s.append(f[1])
            }
            i += hop
        }
        guard f1s.count >= 2 else { return nil }

        func median(_ a: [Double]) -> Double { a.sorted()[a.count / 2] }
        let third = max(1, f1s.count / 3)
        return VowelMeasurement(
            f1: median(f1s), f2: median(f2s), frames: f1s.count,
            earlyF1: median(Array(f1s.prefix(third))), earlyF2: median(Array(f2s.prefix(third))),
            lateF1: median(Array(f1s.suffix(third))), lateF2: median(Array(f2s.suffix(third)))
        )
    }

    // MARK: - fricatives

    struct FricationMeasurement {
        var centreOfGravity: Double
        var voicing: Double
        var highFractionPeak: Double
        var position: Double
    }

    /// The strongest fricative in a region: where its energy sits, and how voiced it is.
    static func frication(_ x: [Float], rate: Double, range: Range<Int>) -> FricationMeasurement? {
        let win = max(16, Int(rate * 0.025)), hop = max(1, Int(rate * 0.008))
        var best: FricationMeasurement?
        var bestHigh = 0.0
        var i = range.lowerBound
        while i + win <= range.upperBound {
            let mag = magnitudeSpectrum(x[i..<(i + win)])
            if mag.isEmpty { i += hop; continue }
            let df = rate / Double(mag.count * 2)
            var low = 0.0, high = 0.0, num = 0.0, den = 0.0
            for k in 1..<mag.count {
                let f = Double(k) * df
                let p = Double(mag[k]) * Double(mag[k])
                if f < 600 { low += p }
                if f > 1800 && f < min(11000, rate / 2) {
                    high += p
                    num += f * Double(mag[k])
                    den += Double(mag[k])
                }
            }
            let fraction = high / (low + high + 1e-12)
            if fraction > 0.55 && high > bestHigh {
                bestHigh = high
                best = FricationMeasurement(
                    centreOfGravity: den > 0 ? num / den : 0,
                    voicing: low / (low + high + 1e-12),
                    highFractionPeak: fraction,
                    position: Double(i - range.lowerBound) / Double(max(1, range.count))
                )
            }
            i += hop
        }
        return best
    }

    /// Quiet stretches inside a region — stop closures, and the gap inside an affricate.
    static func closures(_ x: [Float], rate: Double, range: Range<Int>, minMs: Double = 22) -> [(position: Double, lengthMs: Double)] {
        let env = rmsEnvelope(Array(x[range]), rate: rate, windowMs: 10, hopMs: 4)
        guard !env.values.isEmpty else { return [] }
        let sm = smooth(env.values, radius: 1)
        guard let mx = sm.max(), mx > 0 else { return [] }
        let threshold = mx * 0.13
        let need = Int(minMs / 4)
        var out: [(Double, Double)] = []
        var run = 0
        for i in 0..<sm.count {
            if sm[i] < threshold {
                run += 1
            } else {
                if run >= need {
                    out.append(((Double(i) - Double(run) / 2) / Double(sm.count), Double(run) * 4))
                }
                run = 0
            }
        }
        if run >= need { out.append((1.0, Double(run) * 4)) }
        return out
    }

    // MARK: - perceptual distance

    static func bark(_ f: Double) -> Double {
        13 * atan(0.00076 * f) + 3.5 * atan(pow(f / 7500, 2))
    }

    static func vowelDistance(f1a: Double, f2a: Double, f1b: Double, f2b: Double) -> Double {
        hypot(bark(f1a) - bark(f1b), (bark(f2a) - bark(f2b)) * 0.85)
    }
}
