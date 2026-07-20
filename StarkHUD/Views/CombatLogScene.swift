//
//  CombatLogScene.swift
//  StarkHUD — COMBAT LOG: the last two weeks of workouts filed as
//  mission entries, whatever app logged them.
//

import SwiftUI

struct CombatLogScene: View {
    @Environment(MetricStore.self) private var store

    static let missionClock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MM.dd — HH:mm"
        return f
    }()

    var body: some View {
        let workouts = Array(store.workouts.prefix(7))
        if workouts.isEmpty {
            EmptyLogView()
        } else {
            VStack(spacing: 24) {
                LogSummaryStrip(workouts: workouts)
                HoloPanel {
                    VStack(spacing: 0) {
                        ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                            MissionRow(workout: workout,
                                       isLatest: index == 0,
                                       maxKcal: workouts.compactMap(\.kcal).max() ?? 1)
                            if index < workouts.count - 1 {
                                Divider().overlay(Theme.arcDim.opacity(0.35))
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Summary strip

private struct LogSummaryStrip: View {
    var workouts: [WorkoutEntry]

    var body: some View {
        let totalMinutes = workouts.reduce(0) { $0 + $1.minutes }
        let totalKcal = workouts.compactMap(\.kcal).reduce(0, +)

        HStack(spacing: 30) {
            Text("ENGAGEMENT HISTORY — LAST 14 DAYS")
                .hudLabelStyle(size: 20, color: Theme.gold)
            Spacer()
            summaryStat("\(workouts.count)", "MISSIONS")
            summaryStat(String(format: "%.0f", totalMinutes), "MIN ENGAGED")
            summaryStat(String(format: "%.0f", totalKcal), "KCAL SPENT")
        }
        .padding(.horizontal, 8)
    }

    private func summaryStat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(Theme.hudFont(34, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .hudLabelStyle(size: 15, color: Theme.arcDim)
        }
    }
}

// MARK: - Mission row

private struct MissionRow: View {
    var workout: WorkoutEntry
    var isLatest: Bool
    var maxKcal: Double

    var body: some View {
        HStack(spacing: 22) {
            // Mission insignia.
            ZStack {
                Circle()
                    .strokeBorder(accent.opacity(0.5), lineWidth: 2)
                    .frame(width: 62, height: 62)
                Image(systemName: workout.kind.symbolName)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(accent)
                    .shadow(color: accent.opacity(0.8), radius: 8)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text(workout.kind.missionName)
                        .hudLabelStyle(size: 21, color: isLatest ? Theme.arcBright : Theme.arc)
                    if isLatest {
                        Text("LATEST")
                            .font(Theme.hudFont(13, weight: .bold))
                            .foregroundStyle(Theme.bg)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.gold))
                    }
                }
                Text("\(workout.kind.displayName) · \(CombatLogScene.missionClock.string(from: workout.start).uppercased())")
                    .font(Theme.labelFont(14))
                    .kerning(1.2)
                    .foregroundStyle(Theme.arcDim)
            }

            Spacer()

            statColumn(String(format: "%.0f", workout.minutes), "MIN", width: 110)
            statColumn(workout.km.map { String(format: "%.1f", $0) } ?? "—", "KM", width: 110)
            statColumn(workout.avgHeartRate.map { "\(Int($0))" } ?? "—", "AVG BPM", width: 130)

            // Power expenditure with a relative bar.
            VStack(alignment: .trailing, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(workout.kcal.map { String(format: "%.0f", $0) } ?? "—")
                        .font(Theme.hudFont(30, weight: .bold))
                        .foregroundStyle(Theme.gold)
                    Text("KCAL")
                        .font(Theme.hudFont(13))
                        .foregroundStyle(Theme.gold.opacity(0.7))
                }
                ZStack(alignment: .trailing) {
                    Capsule().fill(Theme.gold.opacity(0.15))
                    Capsule()
                        .fill(Theme.gold.opacity(0.85))
                        .frame(width: 140 * kcalFraction)
                        .shadow(color: Theme.gold.opacity(0.7), radius: 5)
                }
                .frame(width: 140, height: 7)
            }
            .frame(width: 160, alignment: .trailing)
        }
        .padding(.vertical, 14)
    }

    private var accent: Color { isLatest ? Theme.arcBright : Theme.arc }

    private var kcalFraction: Double {
        guard let kcal = workout.kcal, maxKcal > 0 else { return 0 }
        return max(kcal / maxKcal, 0.06)
    }

    private func statColumn(_ value: String, _ label: String, width: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(Theme.hudFont(30, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .hudLabelStyle(size: 13, color: Theme.arcDim)
        }
        .frame(width: width, alignment: .trailing)
    }
}

// MARK: - Empty state

private struct EmptyLogView: View {
    var body: some View {
        HoloPanel(accent: Theme.gold) {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.gold)
                Text("COMBAT LOG EMPTY")
                    .hudLabelStyle(size: 24, color: Theme.gold)
                Text("NO MISSIONS FILED IN THE LAST 14 DAYS — SUIT UP")
                    .font(Theme.labelFont(16))
                    .kerning(1.5)
                    .foregroundStyle(Theme.arcDim)
            }
            .padding(30)
        }
        .frame(maxHeight: .infinity)
    }
}
