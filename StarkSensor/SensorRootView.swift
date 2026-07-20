//
//  SensorRootView.swift
//  StarkSensor — wrist-mounted arc pulse monitor.
//

import SwiftUI

struct SensorRootView: View {
    @Environment(HeartRateStreamer.self) private var streamer

    private let arc = Color(red: 0.42, green: 0.88, blue: 1.00)
    private let gold = Color(red: 1.00, green: 0.76, blue: 0.28)
    private let hot = Color(red: 0.95, green: 0.26, blue: 0.16)

    var body: some View {
        ZStack {
            Color(red: 0.010, green: 0.028, blue: 0.048).ignoresSafeArea()

            VStack(spacing: 10) {
                Text("STARK SENSOR")
                    .font(.system(size: 13, weight: .semibold))
                    .kerning(2.5)
                    .foregroundStyle(gold)

                pulseReadout

                HStack(spacing: 14) {
                    statusDot(on: streamer.phoneReachable, label: "PHONE")
                    statusDot(on: streamer.isStreaming, label: "SENSOR")
                    Text("TX \(streamer.samplesSent)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(arc.opacity(0.7))
                }

                Button {
                    if streamer.isStreaming {
                        streamer.stop()
                    } else {
                        Task { await streamer.start() }
                    }
                } label: {
                    Text(buttonTitle)
                        .font(.system(size: 14, weight: .bold))
                        .kerning(1.5)
                        .foregroundStyle(streamer.isStreaming ? hot : arc)
                }
                .buttonStyle(.bordered)
                .tint(streamer.isStreaming ? hot : arc)
            }
        }
        .onAppear {
            streamer.activatePhoneLink()
        }
    }

    private var buttonTitle: String {
        switch streamer.state {
        case .streaming: return "STOP"
        case .requesting: return "AUTHORIZING…"
        case .denied: return "HEALTH DENIED"
        case .failed: return "RETRY"
        case .idle: return "START STREAM"
        }
    }

    private var pulseReadout: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let bpm = max(streamer.heartRate, 40)
            let period = 60.0 / bpm
            let phase = t.truncatingRemainder(dividingBy: period) / period
            let pulse = streamer.isStreaming ? exp(-5 * phase) : 0

            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(arc)
                    .scaleEffect(1 + 0.16 * pulse)
                    .shadow(color: arc.opacity(0.5 + 0.5 * pulse), radius: 8)

                VStack(alignment: .leading, spacing: 0) {
                    Text(streamer.heartRate > 0 ? "\(Int(streamer.heartRate))" : "——")
                        .font(.system(size: 46, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("BPM — ARC PULSE")
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(1.5)
                        .foregroundStyle(arc.opacity(0.7))
                }
            }
        }
        .frame(height: 70)
    }

    private func statusDot(on: Bool, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(on ? arc : gold)
                .frame(width: 7, height: 7)
                .shadow(color: (on ? arc : gold).opacity(0.8), radius: 4)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .kerning(1)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
