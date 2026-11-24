import AVFoundation

/// Tiny procedural sound effects (no audio files). Off by default; quiet and rate-limited so it never nags.
@MainActor
final class SoundFX {
    static let shared = SoundFX()

    enum Kind: CaseIterable { case hit, arrow, boom, coin, level, legendary }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Kind: AVAudioPCMBuffer] = [:]
    private var next = 0
    private var lastPlay: [Kind: Date] = [:]
    private var started = false
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    private init() {}

    private func start() {
        guard !started else { return }
        started = true
        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 0.22
        for k in Kind.allCases { buffers[k] = synth(k) }
        try? engine.start()
    }

    func play(_ kind: Kind) {
        let gap: TimeInterval = kind == .hit || kind == .arrow ? 0.07 : 0.15
        if let last = lastPlay[kind], Date().timeIntervalSince(last) < gap { return }
        lastPlay[kind] = Date()
        start()
        guard engine.isRunning, let buf = buffers[kind] else { return }
        let p = players[next % players.count]
        next += 1
        p.stop()
        p.scheduleBuffer(buf, at: nil)
        p.play()
    }

    /// Envelope-shaped tones and noise.
    private func synth(_ kind: Kind) -> AVAudioPCMBuffer {
        let sr = 44_100.0
        func notes(_ freqs: [Double], each: Double, decay: Double, square: Bool = false) -> [Float] {
            var out: [Float] = []
            for f in freqs {
                let n = Int(sr * each)
                for i in 0..<n {
                    let t = Double(i) / sr
                    let ph = 2 * Double.pi * f * t
                    let v = square ? (sin(ph) > 0 ? 0.6 : -0.6) : sin(ph)
                    out.append(Float(v * exp(-t * decay)))
                }
            }
            return out
        }
        func noise(_ dur: Double, decay: Double, lowpass: Double) -> [Float] {
            var out: [Float] = [], y = 0.0
            for i in 0..<Int(sr * dur) {
                y += (Double.random(in: -1...1) - y) * lowpass
                out.append(Float(y * exp(-Double(i) / sr * decay)))
            }
            return out
        }
        let samples: [Float]
        switch kind {
        case .hit: samples = noise(0.06, decay: 60, lowpass: 0.5)
        case .arrow: samples = notes([1800, 1200], each: 0.03, decay: 50)
        case .boom: samples = noise(0.28, decay: 12, lowpass: 0.08)
        case .coin: samples = notes([1568, 2093], each: 0.05, decay: 30, square: true)
        case .level: samples = notes([523, 659, 784, 1047], each: 0.07, decay: 18, square: true)
        case .legendary: samples = notes([784, 988, 1175, 1568, 1976], each: 0.09, decay: 10)
        }
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return buf
    }
}
