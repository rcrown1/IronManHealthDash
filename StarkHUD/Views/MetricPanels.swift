//
//  MetricPanels.swift
//  StarkHUD — reusable holographic panels: metric chips, ring gauges,
//  big counters, sparklines.
//

import SwiftUI

// MARK: - Holo panel container

struct HoloPanel<Content: View>: View {
    var accent: Color = Theme.arc
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(22)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.panel)
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(accent.opacity(0.35), lineWidth: 1.5)
                    // Notched corner accents.
                    PanelCorners()
                        .stroke(accent.opacity(0.9), lineWidth: 3)
                }
            }
            .shadow(color: accent.opacity(0.25), radius: 18)
    }
}

/// Short L-shaped strokes at each corner of the panel.
struct PanelCorners: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l: CGFloat = 18
        // Top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        // Top-right
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        // Bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        // Bottom-left
        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return p
    }
}

// MARK: - Sparkline

struct SparklineView: View {
    var values: [Double]
    var color: Color = Theme.arc

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let lo = values.min() ?? 0
            let hi = values.max() ?? 1
            let span = max(hi - lo, 0.0001)
            var path = Path()
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) / CGFloat(values.count - 1) * size.width
                let y = size.height - CGFloat((v - lo) / span) * size.height * 0.9 - size.height * 0.05
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            var glow = ctx
            glow.addFilter(.shadow(color: color.opacity(0.8), radius: 4))
            glow.stroke(path, with: .color(color.opacity(0.9)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Metric chip

struct MetricChip: View {
    var kind: MetricKind
    var sample: MetricSample?
    var history: [Double]
    var accent: Color = Theme.arc

    var body: some View {
        HoloPanel(accent: accent) {
            HStack(spacing: 18) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 44)
                    .shadow(color: accent.opacity(0.8), radius: 8)

                VStack(alignment: .leading, spacing: 5) {
                    Text(kind.starkLabel)
                        .hudLabelStyle(size: 19, color: accent)
                    Text(kind.displayName.uppercased())
                        .font(Theme.labelFont(13))
                        .kerning(1.5)
                        .foregroundStyle(Theme.arcDim)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(sample.map { kind.formatted($0.value) } ?? "——")
                            .font(Theme.hudFont(40, weight: .bold))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text(kind.unitLabel)
                            .font(Theme.hudFont(16))
                            .foregroundStyle(accent.opacity(0.8))
                    }
                }

                Spacer(minLength: 0)

                SparklineView(values: history, color: accent)
                    .frame(width: 90, height: 46)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Ring gauge

struct RingGauge: View {
    var kind: MetricKind
    var value: Double
    var goal: Double
    var color: Color

    private var progress: Double { min(value / max(goal, 1), 1) }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.14), lineWidth: 20)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(colors: [color.opacity(0.5), color],
                                        center: .center,
                                        startAngle: .degrees(0),
                                        endAngle: .degrees(360 * progress)),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.8), radius: 16)
                    .animation(.easeInOut(duration: 1.0), value: progress)

                VStack(spacing: 4) {
                    Text(kind.formatted(value))
                        .font(Theme.hudFont(52, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("/ \(kind.formatted(goal)) \(kind.unitLabel)")
                        .font(Theme.hudFont(17))
                        .foregroundStyle(color.opacity(0.75))
                }
            }
            .frame(width: 260, height: 260)

            Text(kind.starkLabel)
                .hudLabelStyle(size: 21, color: color)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - Big counter

struct BigCounter: View {
    var kind: MetricKind
    var sample: MetricSample?
    var accent: Color = Theme.arc

    var body: some View {
        HoloPanel(accent: accent) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: kind.symbolName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(accent)
                    Text(kind.starkLabel)
                        .hudLabelStyle(size: 18, color: accent)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(sample.map { kind.formatted($0.value) } ?? "——")
                        .font(Theme.hudFont(58, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(kind.unitLabel)
                        .font(Theme.hudFont(19))
                        .foregroundStyle(accent.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
