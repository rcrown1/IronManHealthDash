//
//  RechargeScene.swift
//  StarkHUD — RECHARGE ANALYSIS: last night's sleep as a first-class
//  workshop readout. Hypnogram, stage totals, efficiency, overnight
//  vitals, and a seven-night trend.
//

import SwiftUI

enum SleepPalette {
    static func color(for stage: SleepStage) -> Color {
        switch stage {
        case .awake: return Theme.gold
        case .rem: return Theme.arcBright
        case .light: return Theme.arc
        case .deep: return Color(red: 0.48, green: 0.42, blue: 1.0)
        }
    }

    /// 24-hour clock reads unambiguously on a HUD.
    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

struct RechargeScene: View {
    @Environment(MetricStore.self) private var store

    var body: some View {
        if let night = store.sleepReport?.lastNight {
            content(night: night, trend: store.sleepReport?.recentTotals ?? [])
        } else {
            NoSleepDataView()
        }
    }

    private func content(night: SleepNight, trend: [Double]) -> some View {
        VStack(spacing: 26) {
            HStack(spacing: 26) {
                SleepSummaryPanel(night: night)
                    .frame(width: 470)
                HoloPanel {
                    HypnogramView(night: night)
                        .frame(maxWidth: .infinity)
                        .frame(height: 330)
                }
            }

            HStack(spacing: 26) {
                ForEach([SleepStage.deep, .rem, .light, .awake], id: \.self) { stage in
                    StageTile(stage: stage, night: night)
                }
                OvernightVitalsPanel(night: night)
                SleepTrendPanel(totals: trend)
                    .frame(width: 430)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Summary

private struct SleepSummaryPanel: View {
    var night: SleepNight

    var body: some View {
        HoloPanel {
            VStack(alignment: .leading, spacing: 18) {
                Text("RECHARGE CYCLE")
                    .hudLabelStyle(size: 21)
                Text("LAST NIGHT — SENSOR RING")
                    .font(Theme.labelFont(13))
                    .kerning(1.5)
                    .foregroundStyle(Theme.arcDim)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(format: "%.1f", night.totalHours))
                        .font(Theme.hudFont(84, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: Theme.arc.opacity(0.7), radius: 14)
                    Text("HRS")
                        .font(Theme.hudFont(26))
                        .foregroundStyle(Theme.arc)
                }

                HStack(spacing: 10) {
                    Text(SleepPalette.clock.string(from: night.bedtime))
                    Text("→")
                        .foregroundStyle(Theme.arcDim)
                    Text(SleepPalette.clock.string(from: night.wakeTime))
                }
                .font(Theme.hudFont(28))
                .foregroundStyle(Theme.arcBright)

                Divider().overlay(Theme.arcDim.opacity(0.5))

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("EFFICIENCY")
                            .hudLabelStyle(size: 15)
                        Text("\(Int(night.efficiency * 100))%")
                            .font(Theme.hudFont(40, weight: .bold))
                            .foregroundStyle(night.efficiency >= 0.85 ? Theme.arc : Theme.gold)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("IN CRADLE")
                            .hudLabelStyle(size: 15)
                        Text(String(format: "%.1f HRS", night.inBedHours))
                            .font(Theme.hudFont(40, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Hypnogram

private struct HypnogramView: View {
    var night: SleepNight

    private static let rows: [SleepStage] = [.awake, .rem, .light, .deep]

    var body: some View {
        Canvas { ctx, size in
            let labelWidth: CGFloat = 96
            let axisHeight: CGFloat = 40
            let plot = CGRect(x: labelWidth, y: 8,
                              width: size.width - labelWidth - 8,
                              height: size.height - axisHeight - 8)
            let span = night.wakeTime.timeIntervalSince(night.bedtime)
            guard span > 0 else { return }

            let rowHeight = plot.height / CGFloat(Self.rows.count)

            drawRowGuides(ctx, plot: plot, rowHeight: rowHeight)
            drawHourTicks(ctx, plot: plot, span: span, axisY: plot.maxY + 12)
            drawSegments(ctx, plot: plot, span: span, rowHeight: rowHeight)
        }
    }

    private func rowIndex(_ stage: SleepStage) -> Int {
        Self.rows.firstIndex(of: stage) ?? 0
    }

    private func drawRowGuides(_ ctx: GraphicsContext, plot: CGRect, rowHeight: CGFloat) {
        for (i, stage) in Self.rows.enumerated() {
            let midY = plot.minY + rowHeight * (CGFloat(i) + 0.5)
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: midY))
            line.addLine(to: CGPoint(x: plot.maxX, y: midY))
            ctx.stroke(line, with: .color(Theme.arcDim.opacity(0.25)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 6]))

            ctx.draw(
                Text(stage.displayName)
                    .font(Theme.labelFont(15))
                    .foregroundColor(SleepPalette.color(for: stage).opacity(0.9)),
                at: CGPoint(x: plot.minX - 14, y: midY),
                anchor: .trailing)
        }
    }

    private func drawHourTicks(_ ctx: GraphicsContext, plot: CGRect, span: TimeInterval, axisY: CGFloat) {
        let cal = Calendar.current

        // Bed / wake anchors.
        ctx.draw(Text(SleepPalette.clock.string(from: night.bedtime))
                    .font(Theme.hudFont(16)).foregroundColor(Theme.arc),
                 at: CGPoint(x: plot.minX, y: axisY + 8), anchor: .leading)
        ctx.draw(Text(SleepPalette.clock.string(from: night.wakeTime))
                    .font(Theme.hudFont(16)).foregroundColor(Theme.arc),
                 at: CGPoint(x: plot.maxX, y: axisY + 8), anchor: .trailing)

        // Whole-hour ticks between them.
        var tick = cal.date(bySettingHour: cal.component(.hour, from: night.bedtime),
                            minute: 0, second: 0, of: night.bedtime) ?? night.bedtime
        while tick <= night.wakeTime {
            if tick > night.bedtime {
                let x = plot.minX + plot.width * CGFloat(tick.timeIntervalSince(night.bedtime) / span)
                var line = Path()
                line.move(to: CGPoint(x: x, y: plot.minY))
                line.addLine(to: CGPoint(x: x, y: plot.maxY + 6))
                ctx.stroke(line, with: .color(Theme.arcDim.opacity(0.2)), lineWidth: 1)
            }
            tick = tick.addingTimeInterval(3600)
        }
    }

    private func drawSegments(_ ctx: GraphicsContext, plot: CGRect, span: TimeInterval, rowHeight: CGFloat) {
        var glow = ctx
        glow.addFilter(.shadow(color: Theme.arc.opacity(0.5), radius: 6))

        var previousEnd: CGPoint?
        for segment in night.segments {
            let x0 = plot.minX + plot.width * CGFloat(segment.start.timeIntervalSince(night.bedtime) / span)
            let x1 = plot.minX + plot.width * CGFloat(segment.end.timeIntervalSince(night.bedtime) / span)
            let midY = plot.minY + rowHeight * (CGFloat(rowIndex(segment.stage)) + 0.5)
            let bar = CGRect(x: x0, y: midY - rowHeight * 0.26,
                             width: max(x1 - x0, 2), height: rowHeight * 0.52)
            let color = SleepPalette.color(for: segment.stage)

            glow.fill(Path(roundedRect: bar, cornerRadius: 4), with: .color(color.opacity(0.85)))

            // Step connector from the previous segment.
            if let prev = previousEnd, abs(prev.x - x0) < 4 {
                var connector = Path()
                connector.move(to: prev)
                connector.addLine(to: CGPoint(x: x0, y: midY))
                ctx.stroke(connector, with: .color(Theme.arc.opacity(0.35)), lineWidth: 1.5)
            }
            previousEnd = CGPoint(x: x1, y: midY)
        }
    }
}

// MARK: - Stage tiles

private struct StageTile: View {
    var stage: SleepStage
    var night: SleepNight

    private var hours: Double { night.hours(stage) }
    private var fraction: Double {
        let denominator = stage == .awake
            ? max(night.inBedHours, 0.01)
            : max(night.totalHours, 0.01)
        return min(hours / denominator, 1)
    }

    var body: some View {
        let color = SleepPalette.color(for: stage)
        HoloPanel(accent: color) {
            VStack(alignment: .leading, spacing: 10) {
                Text(stage.displayName)
                    .hudLabelStyle(size: 17, color: color)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(format: "%.1f", hours))
                        .font(Theme.hudFont(36, weight: .bold))
                        .foregroundStyle(.white)
                    Text("HRS")
                        .font(Theme.hudFont(14))
                        .foregroundStyle(color.opacity(0.8))
                }
                .lineLimit(1)
                .fixedSize()
                HStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(color.opacity(0.15))
                            Capsule()
                                .fill(color.opacity(0.9))
                                .frame(width: max(geo.size.width * fraction, 6))
                                .shadow(color: color.opacity(0.8), radius: 6)
                        }
                    }
                    .frame(height: 10)
                    Text("\(Int(fraction * 100))%")
                        .font(Theme.hudFont(17))
                        .foregroundStyle(color.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Overnight vitals

private struct OvernightVitalsPanel: View {
    var night: SleepNight

    var body: some View {
        HoloPanel {
            VStack(alignment: .leading, spacing: 16) {
                Text("OVERNIGHT SYSTEMS")
                    .hudLabelStyle(size: 17)
                vitalRow(symbol: "heart.fill",
                         label: "MIN IDLE FREQ",
                         value: night.lowestHeartRate.map { "\(Int($0)) BPM" } ?? "——")
                vitalRow(symbol: "wind",
                         label: "INTAKE CYCLES",
                         value: night.averageRespiratoryRate.map { String(format: "%.1f BR/MIN", $0) } ?? "——")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func vitalRow(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.arc)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .hudLabelStyle(size: 14, color: Theme.arcDim)
                Text(value)
                    .font(Theme.hudFont(30, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Trend

private struct SleepTrendPanel: View {
    var totals: [Double]

    var body: some View {
        HoloPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("7-NIGHT RECHARGE LOG")
                    .hudLabelStyle(size: 17)
                Canvas { ctx, size in
                    guard !totals.isEmpty else { return }
                    let goal = 8.0
                    let peak = max(totals.max() ?? goal, goal) * 1.1
                    let barWidth = size.width / CGFloat(totals.count) * 0.55
                    let gap = size.width / CGFloat(totals.count)

                    // Goal line at 8 hours.
                    let goalY = size.height * CGFloat(1 - goal / peak)
                    var goalLine = Path()
                    goalLine.move(to: CGPoint(x: 0, y: goalY))
                    goalLine.addLine(to: CGPoint(x: size.width, y: goalY))
                    ctx.stroke(goalLine, with: .color(Theme.gold.opacity(0.6)),
                               style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))

                    for (i, value) in totals.enumerated() {
                        let h = size.height * CGFloat(value / peak)
                        let x = gap * CGFloat(i) + (gap - barWidth) / 2
                        let bar = CGRect(x: x, y: size.height - h, width: barWidth, height: max(h, 2))
                        let isLatest = i == totals.count - 1
                        var glow = ctx
                        glow.addFilter(.shadow(color: Theme.arc.opacity(isLatest ? 0.9 : 0.4),
                                               radius: isLatest ? 10 : 4))
                        glow.fill(Path(roundedRect: bar, cornerRadius: 4),
                                  with: .color(isLatest ? Theme.arcBright : Theme.arc.opacity(0.55)))
                    }
                }
                .frame(height: 120)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Empty state

private struct NoSleepDataView: View {
    var body: some View {
        HoloPanel(accent: Theme.gold) {
            VStack(spacing: 14) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.gold)
                Text("NO RECHARGE DATA")
                    .hudLabelStyle(size: 24, color: Theme.gold)
                Text("SYNC YOUR SLEEP SOURCE (OURA / WATCH) AND OPEN THE COMPANION")
                    .font(Theme.labelFont(16))
                    .kerning(1.5)
                    .foregroundStyle(Theme.arcDim)
            }
            .padding(30)
        }
        .frame(maxHeight: .infinity)
    }
}
