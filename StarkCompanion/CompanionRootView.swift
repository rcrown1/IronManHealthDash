//
//  CompanionRootView.swift
//  StarkCompanion — field uplink status screen, workshop-styled.
//

import SwiftUI

struct CompanionRootView: View {
    @Environment(CompanionViewModel.self) private var model

    private let arc = Color(red: 0.42, green: 0.88, blue: 1.00)
    private let gold = Color(red: 1.00, green: 0.76, blue: 0.28)
    private let bg = Color(red: 0.010, green: 0.028, blue: 0.048)

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        header
                        statusCard
                        metricsCard
                    }
                    .padding(20)
                }
            }
            .preferredColorScheme(.dark)
        }
        .onAppear {
            model.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 6) {
            Text("STARK INDUSTRIES")
                .font(.system(size: 22, weight: .semibold))
                .kerning(4)
                .foregroundStyle(gold)
            Text("FIELD TELEMETRY UPLINK")
                .font(.system(size: 14, weight: .medium))
                .kerning(3)
                .foregroundStyle(arc.opacity(0.7))
        }
        .padding(.top, 12)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusRow(
                label: "APPLE TV LINK",
                value: model.connectedTV.map { $0.uppercased() } ?? "SEARCHING…",
                good: model.connectedTV != nil
            )
            statusRow(
                label: "HEALTHKIT ACCESS",
                value: authLabel,
                good: model.authState == .granted
            )
            statusRow(
                label: "FRAMES TRANSMITTED",
                value: "\(model.framesSent)",
                good: model.framesSent > 0
            )
            if let at = model.lastSentAt {
                statusRow(
                    label: "LAST TRANSMISSION",
                    value: at.formatted(date: .omitted, time: .standard),
                    good: true
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var authLabel: String {
        switch model.authState {
        case .unknown: return "STANDBY"
        case .unavailable: return "UNAVAILABLE"
        case .requesting: return "REQUESTING…"
        case .granted: return "GRANTED"
        case .denied: return "DENIED — CHECK SETTINGS"
        }
    }

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CURRENT TELEMETRY")
                .font(.system(size: 13, weight: .semibold))
                .kerning(2.5)
                .foregroundStyle(arc.opacity(0.7))

            if let payload = model.lastPayload, !payload.samples.isEmpty {
                ForEach(payload.samples) { sample in
                    HStack {
                        Image(systemName: sample.kind.symbolName)
                            .foregroundStyle(arc)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sample.kind.starkLabel)
                                .font(.system(size: 13, weight: .semibold))
                                .kerning(1.2)
                                .foregroundStyle(.white)
                            Text(sample.kind.displayName)
                                .font(.system(size: 11))
                                .foregroundStyle(arc.opacity(0.5))
                        }
                        Spacer()
                        Text("\(sample.kind.formatted(sample.value)) \(sample.kind.unitLabel)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(arc)
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Text("Awaiting first HealthKit snapshot…")
                    .font(.system(size: 14))
                    .foregroundStyle(arc.opacity(0.5))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: Pieces

    private func statusRow(label: String, value: String, good: Bool) -> some View {
        HStack {
            Circle()
                .fill(good ? arc : gold)
                .frame(width: 9, height: 9)
                .shadow(color: (good ? arc : gold).opacity(0.8), radius: 5)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .kerning(1.5)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(good ? arc : gold)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(red: 0.030, green: 0.095, blue: 0.140).opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(arc.opacity(0.3), lineWidth: 1)
            )
    }
}
