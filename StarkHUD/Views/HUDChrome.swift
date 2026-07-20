//
//  HUDChrome.swift
//  StarkHUD — persistent framing: header bar, corner brackets, and the
//  JARVIS-style diagnostic ticker.
//

import SwiftUI

// MARK: - Header

struct HUDHeader: View {
    var sceneTitle: String
    @Environment(MetricStore.self) private var store

    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 12) {
                Text("STARK INDUSTRIES")
                    .hudLabelStyle(size: 24, color: Theme.gold)
                Text("// BIOMETRIC TELEMETRY")
                    .hudLabelStyle(size: 24, color: Theme.arcDim)
            }

            Spacer()

            HStack(spacing: 14) {
                Text("‹")
                    .font(Theme.hudFont(26))
                    .foregroundStyle(Theme.arcDim)
                Text(sceneTitle)
                    .hudLabelStyle(size: 26, color: Theme.arcBright)
                Text("›")
                    .font(Theme.hudFont(26))
                    .foregroundStyle(Theme.arcDim)
            }

            Spacer()

            HStack(spacing: 20) {
                LinkBadge()
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(timeline.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
                        .font(Theme.hudFont(24))
                        .foregroundStyle(Theme.arc)
                }
            }
        }
    }
}

/// Uplink status pill: green-ish glow when the phone is streaming,
/// amber pulse while in simulation.
struct LinkBadge: View {
    @Environment(MetricStore.self) private var store

    private var isLive: Bool { store.mode == .live }

    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let blink = 0.55 + 0.45 * sin(t * (isLive ? 2.4 : 5.0))
                Circle()
                    .fill(isLive ? Theme.arc : Theme.gold)
                    .frame(width: 13, height: 13)
                    .opacity(blink)
                    .shadow(color: (isLive ? Theme.arc : Theme.gold).opacity(blink), radius: 8)
            }
            Text(isLive ? "UPLINK \(store.sourceName.uppercased())" : "SIMULATION MODE")
                .hudLabelStyle(size: 18, color: isLive ? Theme.arc : Theme.gold)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .strokeBorder((isLive ? Theme.arc : Theme.gold).opacity(0.4), lineWidth: 1.5)
        )
    }
}

// MARK: - Corner brackets

struct CornerBrackets: View {
    var body: some View {
        GeometryReader { geo in
            let l: CGFloat = 64
            Path { p in
                let r = CGRect(origin: .zero, size: geo.size)
                p.move(to: CGPoint(x: r.minX, y: r.minY + l))
                p.addLine(to: CGPoint(x: r.minX, y: r.minY))
                p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))

                p.move(to: CGPoint(x: r.maxX - l, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))

                p.move(to: CGPoint(x: r.maxX, y: r.maxY - l))
                p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))

                p.move(to: CGPoint(x: r.minX + l, y: r.maxY))
                p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
            }
            .stroke(Theme.arc.opacity(0.5), lineWidth: 3)
            .shadow(color: Theme.arc.opacity(0.4), radius: 8)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Ticker

/// Rotating diagnostic chatter along the bottom edge, blending live data
/// readouts with workshop flavor.
struct TickerView: View {
    @Environment(MetricStore.self) private var store
    @State private var index = 0

    private static let flavor = [
        "RUNNING SUIT INTEGRITY CHECK … ALL SYSTEMS NOMINAL",
        "CALIBRATING REPULSOR ALIGNMENT … WITHIN TOLERANCE",
        "HOUSE PROTOCOL: WORKSHOP CLIMATE STABLE",
        "DIAGNOSTIC SWEEP COMPLETE — NO ANOMALIES DETECTED",
        "TELEMETRY BUFFER SYNCHRONIZED",
        "NEURAL LINK LATENCY: 3MS — OPTIMAL",
        "POWER CELLS CYCLING WITHIN SPEC",
        "ATMOSPHERIC SCRUBBERS ONLINE",
    ]

    private var messages: [String] {
        var lines: [String] = []
        if let hr = store.sample(.heartRate) {
            lines.append("ARC PULSE \(Int(hr.value)) BPM — \(hr.value > 120 ? "ELEVATED OUTPUT" : "NOMINAL")")
        }
        if let e = store.sample(.activeEnergy) {
            lines.append(String(format: "POWER DRAW %.0f KCAL — %.0f%% OF DAILY CELL BUDGET",
                                e.value, min(e.value / store.energyGoal, 1.5) * 100))
        }
        if let s = store.sample(.steps) {
            lines.append("LOCOMOTION UNITS LOGGED: \(Int(s.value))")
        }
        if let o = store.sample(.bloodOxygen) {
            lines.append(String(format: "O₂ SATURATION %.0f%% — LIFE SUPPORT UNNECESSARY", o.value))
        }
        if let night = store.sleepReport?.lastNight {
            lines.append(String(format: "LAST RECHARGE: %.1f HRS — EFFICIENCY %.0f%% — DEEP %.1f HRS",
                                night.totalHours, night.efficiency * 100, night.hours(.deep)))
        } else if let sl = store.sample(.sleepHours) {
            lines.append(String(format: "LAST RECHARGE CYCLE: %.1f HRS", sl.value))
        }
        if let mission = store.workouts.first {
            let kcalText = mission.kcal.map { String(format: " / %.0f KCAL", $0) } ?? ""
            lines.append("LAST MISSION: \(mission.kind.missionName) — \(Int(mission.minutes)) MIN\(kcalText)")
        }
        if let asymmetry = store.mobility?.asymmetry {
            lines.append(String(format: "SERVO SYMMETRY DRIFT %.1f%% — %@", asymmetry,
                                asymmetry <= 5 ? "WITHIN TOLERANCE" : "RECALIBRATION ADVISED"))
        }
        // Interleave flavor between data lines.
        var mixed: [String] = []
        for (i, l) in lines.enumerated() {
            mixed.append(l)
            mixed.append(Self.flavor[i % Self.flavor.count])
        }
        return mixed.isEmpty ? Self.flavor : mixed
    }

    var body: some View {
        HStack(spacing: 16) {
            Text("▸")
                .font(Theme.hudFont(20))
                .foregroundStyle(Theme.gold)
            Text(messages[index % messages.count])
                .font(Theme.hudFont(20))
                .foregroundStyle(Theme.arc.opacity(0.75))
                .lineLimit(1)
                .id(index)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity))
            Spacer()
        }
        .frame(height: 34)
        .clipped()
        .onReceive(Timer.publish(every: 4.5, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                index += 1
            }
        }
    }
}
