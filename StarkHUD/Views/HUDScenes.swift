//
//  HUDScenes.swift
//  StarkHUD — the four display modes the workshop cycles through.
//

import SwiftUI

enum HUDScene: Int, CaseIterable {
    case arcCore
    case vitals
    case power
    case recharge
    case combatLog
    case mobility
    case diagnostics

    var title: String {
        switch self {
        case .arcCore: return "ARC CORE"
        case .vitals: return "VITAL SIGNS"
        case .power: return "POWER SYSTEMS"
        case .recharge: return "RECHARGE ANALYSIS"
        case .combatLog: return "COMBAT LOG"
        case .mobility: return "CHASSIS MOBILITY"
        case .diagnostics: return "FULL DIAGNOSTICS"
        }
    }

    var next: HUDScene {
        HUDScene(rawValue: (rawValue + 1) % HUDScene.allCases.count) ?? .arcCore
    }

    var previous: HUDScene {
        HUDScene(rawValue: (rawValue + HUDScene.allCases.count - 1) % HUDScene.allCases.count) ?? .arcCore
    }
}

// MARK: - Scene 1: Arc core with orbiting metric chips

struct ArcCoreScene: View {
    @Environment(MetricStore.self) private var store
    @State private var chipOffset = 0

    /// Everything except heart rate rotates through the six side slots.
    private static let pool: [MetricKind] = MetricKind.allCases.filter { $0 != .heartRate }

    private func kind(_ slot: Int) -> MetricKind {
        Self.pool[(chipOffset + slot) % Self.pool.count]
    }

    private func chip(_ slot: Int) -> some View {
        let k = kind(slot)
        return MetricChip(kind: k, sample: store.sample(k), history: store.sparkline(k))
            .id("\(slot)-\(k.rawValue)")
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: slot < 3 ? .leading : .trailing)),
                removal: .opacity))
    }

    var body: some View {
        HStack(spacing: 40) {
            VStack(spacing: 26) {
                chip(0); chip(1); chip(2)
            }
            .frame(width: 480)

            VStack(spacing: 8) {
                ArcReactorView(bpm: store.bpm)
                    .frame(width: 560, height: 560)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(Int(store.bpm))")
                        .font(Theme.hudFont(76, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .shadow(color: Theme.arc.opacity(0.8), radius: 16)
                    Text("BPM")
                        .font(Theme.hudFont(28))
                        .foregroundStyle(Theme.arc)
                }
                Text("ARC PULSE")
                    .hudLabelStyle(size: 20)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 26) {
                chip(3); chip(4); chip(5)
            }
            .frame(width: 480)
        }
        .frame(maxHeight: .infinity)
        .onReceive(Timer.publish(every: 6, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.8)) {
                chipOffset += 1
            }
        }
    }
}

// MARK: - Scene 2: Vitals wall with EKG

struct VitalsScene: View {
    @Environment(MetricStore.self) private var store

    private static let vitalKinds: [MetricKind] = [
        .heartRateVariability, .bloodOxygen, .respiratoryRate, .restingHeartRate, .vo2Max,
    ]

    var body: some View {
        VStack(spacing: 36) {
            HoloPanel {
                ZStack(alignment: .topLeading) {
                    EKGWaveformView(bpm: store.bpm)
                        .frame(height: 330)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(Int(store.bpm))")
                            .font(Theme.hudFont(64, weight: .bold))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text("BPM — CARDIAC TRACE")
                            .hudLabelStyle(size: 20)
                    }
                    .padding(.top, 6)
                    .padding(.leading, 8)
                    .shadow(color: .black.opacity(0.8), radius: 10)
                }
            }

            HStack(spacing: 26) {
                ForEach(Self.vitalKinds) { k in
                    VitalTile(kind: k, sample: store.sample(k), history: store.sparkline(k))
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// Compact vertical tile used on the vitals wall.
struct VitalTile: View {
    var kind: MetricKind
    var sample: MetricSample?
    var history: [Double]

    var body: some View {
        HoloPanel {
            VStack(spacing: 12) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Theme.arc)
                    .shadow(color: Theme.arc.opacity(0.8), radius: 8)
                Text(kind.starkLabel)
                    .hudLabelStyle(size: 17)
                    .multilineTextAlignment(.center)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(sample.map { kind.formatted($0.value) } ?? "——")
                        .font(Theme.hudFont(46, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(kind.unitLabel)
                        .font(Theme.hudFont(15))
                        .foregroundStyle(Theme.arc.opacity(0.8))
                }
                SparklineView(values: history)
                    .frame(height: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Scene 3: Power systems (activity)

struct PowerScene: View {
    @Environment(MetricStore.self) private var store

    var body: some View {
        HStack(spacing: 60) {
            HStack(spacing: 56) {
                RingGauge(kind: .activeEnergy,
                          value: store.value(.activeEnergy),
                          goal: store.energyGoal,
                          color: Theme.hotRod)
                RingGauge(kind: .exerciseMinutes,
                          value: store.value(.exerciseMinutes),
                          goal: store.exerciseGoal,
                          color: Theme.gold)
                RingGauge(kind: .standHours,
                          value: store.value(.standHours),
                          goal: store.standGoal,
                          color: Theme.arc)
            }

            VStack(spacing: 26) {
                BigCounter(kind: .steps, sample: store.sample(.steps))
                BigCounter(kind: .distanceWalkingRunning, sample: store.sample(.distanceWalkingRunning))
                BigCounter(kind: .flightsClimbed, sample: store.sample(.flightsClimbed))
            }
            .frame(width: 460)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Scene 4: Full diagnostics grid

struct DiagnosticsScene: View {
    @Environment(MetricStore.self) private var store

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: 4)

    var body: some View {
        ZStack {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(MetricKind.allCases) { k in
                    DiagnosticCell(kind: k, sample: store.sample(k), history: store.sparkline(k))
                }
            }

            // Scanner sweep passing over the grid.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                GeometryReader { geo in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let x = (t / 7.0).truncatingRemainder(dividingBy: 1.0) * (geo.size.width + 260) - 130
                    LinearGradient(colors: [Theme.arc.opacity(0), Theme.arc.opacity(0.10), Theme.arc.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 260)
                        .offset(x: x)
                }
            }
            .allowsHitTesting(false)
        }
        .frame(maxHeight: .infinity)
    }
}

struct DiagnosticCell: View {
    var kind: MetricKind
    var sample: MetricSample?
    var history: [Double]

    var body: some View {
        HoloPanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: kind.symbolName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.arc)
                    Text(kind.starkLabel)
                        .hudLabelStyle(size: 14)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(sample.map { kind.formatted($0.value) } ?? "——")
                        .font(Theme.hudFont(36, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(kind.unitLabel)
                        .font(Theme.hudFont(13))
                        .foregroundStyle(Theme.arc.opacity(0.7))
                    Spacer()
                    SparklineView(values: history)
                        .frame(width: 70, height: 30)
                }
            }
        }
    }
}
