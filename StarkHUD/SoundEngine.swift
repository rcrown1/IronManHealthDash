//
//  SoundEngine.swift
//  StarkHUD — procedural workshop audio. Every sound is synthesized at
//  launch (no assets): a low reactor hum, boot sweep, scene whooshes,
//  uplink chirps, ticker blips, and a heartbeat thump that follows the
//  wearer's live BPM.
//

import AVFoundation
import Observation

@MainActor
@Observable
final class SoundEngine {

    private let engine = AVAudioEngine()
    private let ambientPlayer = AVAudioPlayerNode()
    private let fxPlayer = AVAudioPlayerNode()
    private let beatPlayer = AVAudioPlayerNode()

    private var humBuffer: AVAudioPCMBuffer?
    private var bootBuffer: AVAudioPCMBuffer?
    private var whooshBuffer: AVAudioPCMBuffer?
    private var uplinkBuffer: AVAudioPCMBuffer?
    private var offlineBuffer: AVAudioPCMBuffer?
    private var tickerBuffer: AVAudioPCMBuffer?
    private var beatBuffer: AVAudioPCMBuffer?

    private(set) var isEnabled = true
    private var started = false

    private static let sampleRate = 44100.0

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true

        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate,
                                         channels: 1) else { return }

        humBuffer = Self.makeHumLoop(format: format)
        bootBuffer = Self.makeBoot(format: format)
        whooshBuffer = Self.makeWhoosh(format: format)
        uplinkBuffer = Self.makeUplink(format: format)
        offlineBuffer = Self.makeOffline(format: format)
        tickerBuffer = Self.makeTickerBlip(format: format)
        beatBuffer = Self.makeBeatThump(format: format)

        engine.attach(ambientPlayer)
        engine.attach(fxPlayer)
        engine.attach(beatPlayer)
        engine.connect(ambientPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(fxPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(beatPlayer, to: engine.mainMixerNode, format: format)

        ambientPlayer.volume = 0.20   // barely-there reactor bed
        fxPlayer.volume = 0.50
        beatPlayer.volume = 0.35

        do {
            try engine.start()
        } catch {
            return
        }

        if let hum = humBuffer {
            ambientPlayer.scheduleBuffer(hum, at: nil, options: .loops)
            ambientPlayer.play()
        }
        if let boot = bootBuffer {
            fxPlayer.scheduleBuffer(boot)
            fxPlayer.play()
        }
    }

    func toggleEnabled() {
        isEnabled.toggle()
        engine.mainMixerNode.outputVolume = isEnabled ? 1 : 0
    }

    // MARK: One-shots

    private func playFX(_ buffer: AVAudioPCMBuffer?) {
        guard started, isEnabled, engine.isRunning, let buffer else { return }
        fxPlayer.scheduleBuffer(buffer)
        if !fxPlayer.isPlaying { fxPlayer.play() }
    }

    func playTransition() { playFX(whooshBuffer) }
    func playUplinkEstablished() { playFX(uplinkBuffer) }
    func playUplinkLost() { playFX(offlineBuffer) }
    func playTickerBlip() { playFX(tickerBuffer) }

    func playBeat() {
        guard started, isEnabled, engine.isRunning, let beatBuffer else { return }
        beatPlayer.scheduleBuffer(beatBuffer)
        if !beatPlayer.isPlaying { beatPlayer.play() }
    }

    // MARK: Synthesis

    /// Renders `duration` seconds through a pure sample function of time.
    private static func render(format: AVAudioFormat, duration: Double,
                               _ sample: (Double) -> Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            data[i] = Float(max(min(sample(t), 1), -1))
        }
        return buffer
    }

    private static func sine(_ freq: Double, _ t: Double) -> Double {
        sin(2 * .pi * freq * t)
    }

    /// Linear-sweep phase: freq goes f0 → f1 over `duration`.
    private static func sweepPhase(_ f0: Double, _ f1: Double, _ duration: Double, _ t: Double) -> Double {
        let k = (f1 - f0) / duration
        return 2 * .pi * (f0 * t + k * t * t / 2)
    }

    /// Seamless 6-second reactor hum: harmonics chosen to complete whole
    /// cycles in the loop, with a slow two-cycle swell.
    private static func makeHumLoop(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let d = 6.0
        return render(format: format, duration: d) { t in
            let swell = 0.75 + 0.25 * sin(2 * .pi * t / 3.0)
            let hum = 0.50 * sine(55, t)
                    + 0.28 * sine(110, t)
                    + 0.10 * sine(165, t)
                    + 0.05 * sine(220, t)
            return hum * swell * 0.55
        }
    }

    /// Power-up: rising sweep, then a two-tone confirmation chime.
    private static func makeBoot(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        render(format: format, duration: 1.8) { t in
            var s = 0.0
            if t < 1.0 {
                let env = sin(.pi * t) * 0.5
                s += sin(sweepPhase(150, 620, 1.0, t)) * env * 0.6
                s += sin(sweepPhase(300, 1240, 1.0, t)) * env * 0.2
            }
            if t >= 1.0 {
                let u = t - 1.0
                let env = exp(-4.5 * u)
                s += (0.45 * sine(880, u) + 0.30 * sine(1318.5, u)) * env
            }
            return s
        }
    }

    /// Scene change: airy noise burst with a falling tone underneath.
    private static func makeWhoosh(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var seed: UInt64 = 0x5747_1DEA
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(Int64(bitPattern: seed >> 11)) / Double(Int64.max)
        }
        return render(format: format, duration: 0.55) { t in
            let env = pow(sin(.pi * t / 0.55), 2.0) * exp(-2.5 * t)
            let air = noise() * 0.30
            let tone = sin(sweepPhase(950, 280, 0.55, t)) * 0.35
            return (air + tone) * env
        }
    }

    /// Three ascending notes — uplink established.
    private static func makeUplink(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let notes: [(start: Double, freq: Double)] = [(0.0, 659), (0.13, 880), (0.26, 1175)]
        return render(format: format, duration: 0.85) { t in
            var s = 0.0
            for note in notes where t >= note.start {
                let u = t - note.start
                s += sine(note.freq, u) * exp(-9 * u) * 0.40
            }
            return s
        }
    }

    /// Two descending notes — uplink lost, simulation resumes.
    private static func makeOffline(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let notes: [(start: Double, freq: Double)] = [(0.0, 740), (0.16, 440)]
        return render(format: format, duration: 0.7) { t in
            var s = 0.0
            for note in notes where t >= note.start {
                let u = t - note.start
                s += sine(note.freq, u) * exp(-8 * u) * 0.38
            }
            return s
        }
    }

    /// Tiny telemetry tick for the diagnostic ticker.
    private static func makeTickerBlip(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        render(format: format, duration: 0.07) { t in
            sine(1245, t) * exp(-55 * t) * 0.16
        }
    }

    /// Sub-bass thump, pitch dropping 52 → 38 Hz — the arc pulse.
    private static func makeBeatThump(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        render(format: format, duration: 0.16) { t in
            let env = exp(-16 * t)
            let thump = sin(sweepPhase(52, 38, 0.16, t))
            let knock = sine(104, t) * 0.2
            return (thump + knock) * env * 0.7
        }
    }
}
