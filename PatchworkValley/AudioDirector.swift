import Accelerate
import AVFoundation

/// The game's sound effects: short cues held in memory and played through one audio engine.
/// Each cue's file lives in `Sounds/`, named by the cue (`select_spot.wav`); a cue with no file stays silent.
/// The session is `.ambient`, so the silent switch mutes the game and the player's own music keeps playing.
final class AudioDirector {
    enum Cue: String, CaseIterable {
        case selectSpot = "select_spot"

        /// How loud the cue plays, from 0 to 1. Loading brings every file to the same peak, so this sets the mix.
        var gain: Float {
            switch self {
            case .selectSpot: 0.05
            }
        }
    }

    private var engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private var voices: [Voice] = []
    private var idleStop: Task<Void, Never>?
    private var resetObserver: NSObjectProtocol?

    /// One player with its own varispeed, so each play can be pitched a little differently.
    private struct Voice {
        let player = AVAudioPlayerNode()
        let pitch = AVAudioUnitVarispeed()
        var busyUntil: TimeInterval = 0
    }

    private static let voiceCount = 8
    /// How far a cue may drift from its recorded pitch on each play, so repeats don't sound mechanical.
    private static let pitchSpread = 40.0
    /// Generated files come out at very different levels, so each one is scaled to this peak as it loads.
    private static let loadedPeak: Float = 0.9
    /// Leading samples more than 30 dB below a file's peak are trimmed, so taps sound the instant they happen.
    private static let leadingSilence: Float = 0.03
    /// Everything below this is filtered out as a file loads. Phone speakers can't play it, pushing it at them makes
    /// iOS's speaker protection clamp down (which sounds gritty), and it would set the level by a thump nobody hears.
    private static let lowCut = 150.0

    init() {
        for cue in Cue.allCases {
            if let buffer = Self.load(cue, as: format) { buffers[cue] = buffer }
        }
        guard !buffers.isEmpty else { return }
        buildVoices()
        // A media services reset orphans every audio object, so the engine and its voices are built again.
        // The next sound starts the new engine and sets up the session again.
        resetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.idleStop?.cancel()
                self.engine = AVAudioEngine()
                self.buildVoices()
            }
        }
    }

    private func buildVoices() {
        voices = (0..<Self.voiceCount).map { _ in
            let voice = Voice()
            engine.attach(voice.player)
            engine.attach(voice.pitch)
            engine.connect(voice.player, to: voice.pitch, format: format)
            engine.connect(voice.pitch, to: engine.mainMixerNode, format: format)
            return voice
        }
    }

    func play(_ cue: Cue) {
        guard let buffer = buffers[cue], startIfNeeded() else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // A free voice if there is one, otherwise the one that finishes soonest.
        let index = voices.indices.first { voices[$0].busyUntil <= now }
            ?? voices.indices.min { voices[$0].busyUntil < voices[$1].busyUntil }!
        let rate = Float(pow(2, Double.random(in: -Self.pitchSpread...Self.pitchSpread) / 1200))
        let voice = voices[index]
        voice.player.stop()
        voice.player.volume = cue.gain
        voice.pitch.rate = rate
        voice.player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        voice.player.play()
        voices[index].busyUntil = now + Double(buffer.frameLength) / format.sampleRate / Double(rate)
        stopWhenIdle()
    }

    /// Starts the engine for a sound, reactivating the session after an interruption or a route change stopped it.
    private func startIfNeeded() -> Bool {
        if engine.isRunning { return true }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient)
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    /// A running engine keeps the audio hardware awake, so it pauses once the game has been quiet for a while.
    private func stopWhenIdle() {
        idleStop?.cancel()
        idleStop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.engine.pause()
        }
    }

    /// Reads a cue's file into memory in the engine's format: high-passed at `lowCut`, without its leading silence,
    /// and scaled to `loadedPeak`.
    private static func load(_ cue: Cue, as format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let url = ["wav", "caf", "m4a", "mp3"].lazy.compactMap {
            Bundle.main.url(forResource: cue.rawValue, withExtension: $0)
                ?? Bundle.main.url(forResource: cue.rawValue, withExtension: $0, subdirectory: "Sounds")
        }.first
        guard let url, let file = try? AVAudioFile(forReading: url),
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: source)) != nil,
              let converter = AVAudioConverter(from: file.processingFormat, to: format) else { return nil }
        let ratio = format.sampleRate / file.processingFormat.sampleRate
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(source.frameLength) * ratio) + 1024) else { return nil }
        // Stereo files fold both channels into the mono voice instead of keeping only the left one.
        converter.downmix = true
        let input = SingleInput(source)
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in input.next(status) }
        guard error == nil, let raw = converted.floatChannelData?[0] else { return nil }
        let length = Int(converted.frameLength)
        let samples = highPassed(Array(UnsafeBufferPointer(start: raw, count: length)), sampleRate: format.sampleRate)
        let peak = (0..<length).reduce(Float(0)) { max($0, abs(samples[$1])) }
        guard peak > 0 else { return nil }
        let start = (0..<length).first { abs(samples[$0]) > peak * leadingSilence } ?? 0
        guard let trimmed = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length - start)),
              let target = trimmed.floatChannelData?[0] else { return nil }
        let scale = loadedPeak / peak
        for i in 0..<(length - start) { target[i] = samples[start + i] * scale }
        trimmed.frameLength = AVAudioFrameCount(length - start)
        return trimmed
    }

    /// A 4th-order Butterworth high-pass at `lowCut`, as two biquad sections (Audio EQ Cookbook).
    private static func highPassed(_ samples: [Float], sampleRate: Double) -> [Float] {
        let w = 2 * Double.pi * lowCut / sampleRate
        let coefficients = [0.541_196_1, 1.306_563].flatMap { q -> [Double] in
            let alpha = sin(w) / (2 * q)
            let a0 = 1 + alpha
            return [(1 + cos(w)) / 2 / a0, -(1 + cos(w)) / a0, (1 + cos(w)) / 2 / a0, -2 * cos(w) / a0, (1 - alpha) / a0]
        }
        guard var filter = vDSP.Biquad(coefficients: coefficients, channelCount: 1, sectionCount: 2, ofType: Float.self) else {
            return samples
        }
        return filter.apply(input: samples)
    }
}

/// Hands the converter its one input buffer, then reports the end of the stream. The converter calls
/// it synchronously inside `convert(to:error:withInputFrom:)`, so it is never used from two threads at once.
private nonisolated final class SingleInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .endOfStream
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}
