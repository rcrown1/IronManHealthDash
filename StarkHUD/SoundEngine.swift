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
        whooshBuffer = Self.makeSuitLock(format: format)
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

    /// Power-up in three acts: sub rumble builds under a charging sweep
    /// while capacitor ticks accelerate, then ignition — a sub thump and
    /// a triumphant chord with a high shimmer.
    private static func makeBoot(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Charge ticks that speed up as the banks come online. The interval
        // is floored so the series always reaches the cutoff and terminates.
        var tickTimes: [Double] = []
        var tick = 0.25
        var interval = 0.30
        while tick < 2.05 {
            tickTimes.append(tick)
            interval = max(interval * 0.80, 0.045)
            tick += interval
        }

        let sweepDuration = 2.3
        let ratio = pow(820.0 / 85.0, 1.0 / sweepDuration)
        let lnRatio = log(ratio)
        let ignition = 2.35

        var seed: UInt64 = 0xA11C_E5E7
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(Int64(bitPattern: seed >> 11)) / Double(Int64.max)
        }

        return render(format: format, duration: 3.8) { t in
            var s = 0.0

            // Act 1: sub rumble fading in underneath everything.
            if t < ignition {
                let build = min(t / 1.6, 1.0)
                s += sin(2 * .pi * 42 * t) * 0.20 * build
                s += noise() * 0.05 * build
            }

            // Act 2: exponential charging whine with a harmonic above it.
            if t < sweepDuration {
                let phase = 2 * .pi * 85.0 * (pow(ratio, t) - 1) / lnRatio
                let fadeIn = min(t / 0.5, 1.0)
                let fadeOut = t < 2.05 ? 1.0 : max(0, (sweepDuration - t) / 0.25)
                let env = fadeIn * fadeOut
                s += sin(phase) * 0.28 * env
                s += sin(phase * 2) * 0.11 * env
            }

            // Accelerating capacitor ticks.
            for tickTime in tickTimes where t >= tickTime && t < tickTime + 0.05 {
                let u = t - tickTime
                s += sin(2 * .pi * 1150 * u) * exp(-160 * u) * 0.28
            }

            // Act 3: ignition — sub thump, chord, shimmer.
            if t >= ignition {
                let u = t - ignition
                s += sin(sweepPhase(95, 44, 0.3, min(u, 0.3))) * exp(-9 * u) * 0.45
                let chord = 0.26 * sine(880, u)
                          + 0.20 * sine(1108.7, u)
                          + 0.16 * sine(1318.5, u)
                s += chord * exp(-2.4 * u)
                s += sine(2637, u) * exp(-4 * u) * 0.06
            }
            return s * 0.9
        }
    }

    /// Scene change: a heavy metal door sliding shut. Rolling rumble and
    /// metal-on-metal scrape while it moves, a big stop-clunk when it
    /// hits the frame, and one low bolt-latch to seal it.
    private static func makeSuitLock(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var seed: UInt64 = 0x5117_10CC
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(Int64(bitPattern: seed >> 11)) / Double(Int64.max)
        }

        let slideEnd = 0.58
        let latchAt = 0.80
        var lowState = 0.0   // one-pole filter memory; render runs sequentially

        return render(format: format, duration: 1.1) { t in
            var s = 0.0
            let n = noise()
            lowState += 0.045 * (n - lowState)

            // The door in motion: low rolling mass + scrape residue,
            // ramping in fast and decelerating into the frame.
            if t < slideEnd {
                let ramp = min(t / 0.07, 1.0)
                let decel = t < 0.44 ? 1.0 : max(0, (slideEnd - t) / 0.14)
                // Roller flutter — the door jitters as it travels.
                let flutter = 0.72 + 0.18 * sin(2 * .pi * 23 * t) + 0.10 * sin(2 * .pi * 37 * t)
                let env = ramp * decel * flutter
                s += lowState * 1.5 * env                       // rolling rumble
                s += (n - lowState) * 0.055 * env               // metal scrape
                s += sine(46, t) * 0.10 * env                   // sheer mass
            }

            // The door hits the frame: deep clunk with damped body modes.
            if t >= slideEnd {
                let u = t - slideEnd
                if u < 0.007 { s += n * 0.6 }
                s += sine(64, u) * exp(-22 * u) * 0.55
                s += sine(255, u) * exp(-30 * u) * 0.20
                s += sine(492, u) * exp(-38 * u) * 0.11
            }

            // One low bolt seats to seal it.
            if t >= latchAt {
                let u = t - latchAt
                if u < 0.004 { s += n * 0.35 }
                s += sine(690, u) * exp(-60 * u) * 0.16
                s += sine(1130, u) * exp(-80 * u) * 0.07
            }
            return s
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
