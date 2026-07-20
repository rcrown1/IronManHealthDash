//
//  ArcReactorView.swift
//  StarkHUD — a procedurally drawn arc reactor whose pulse is driven
//  by the wearer's live heart rate.
//

import SwiftUI

struct ArcReactorView: View {
    var bpm: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2

                // One heartbeat = one reactor surge. exp decay gives the "thump".
                let period = 60.0 / max(bpm, 30)
                let phase = t.truncatingRemainder(dividingBy: period) / period
                let pulse = exp(-4.5 * phase)

                drawOuterGlow(ctx, center: center, radius: radius, pulse: pulse)
                drawTickRing(ctx, center: center, radius: radius * 0.97, t: t)
                drawRotatingArcs(ctx, center: center, radius: radius, t: t)
                drawCoilSegments(ctx, center: center, radius: radius, t: t, pulse: pulse)
                drawCore(ctx, center: center, radius: radius, pulse: pulse)
            }
        }
    }

    // MARK: Layers

    private func drawOuterGlow(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat, pulse: Double) {
        let r = radius * 1.0
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect),
                 with: .radialGradient(
                    Gradient(colors: [
                        Theme.arc.opacity(0.10 + 0.10 * pulse),
                        Theme.arc.opacity(0.0),
                    ]),
                    center: center, startRadius: radius * 0.2, endRadius: r))
    }

    private func drawTickRing(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat, t: Double) {
        var ring = ctx
        ring.addFilter(.shadow(color: Theme.arc.opacity(0.8), radius: 6))

        // Outer boundary circle.
        let outer = CGRect(x: center.x - radius, y: center.y - radius,
                           width: radius * 2, height: radius * 2)
        ring.stroke(Path(ellipseIn: outer), with: .color(Theme.arc.opacity(0.85)), lineWidth: 2.5)

        // 72 tick marks, every fifth one long — a machinist's dial.
        var ticks = Path()
        for i in 0..<72 {
            let a = Double(i) / 72 * 2 * .pi
            let dx = CGFloat(cos(a))
            let dy = CGFloat(sin(a))
            let long = i % 5 == 0
            let r0 = radius * (long ? 0.905 : 0.935)
            let r1 = radius * 0.975
            ticks.move(to: CGPoint(x: center.x + dx * r0, y: center.y + dy * r0))
            ticks.addLine(to: CGPoint(x: center.x + dx * r1, y: center.y + dy * r1))
        }
        ring.stroke(ticks, with: .color(Theme.arc.opacity(0.55)), lineWidth: 2)
    }

    /// Counter-rotating dashed rings — the illusion of spinning machinery,
    /// done cheaply by animating dash phase.
    private func drawRotatingArcs(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat, t: Double) {
        var ring = ctx
        ring.addFilter(.shadow(color: Theme.arc.opacity(0.9), radius: 10))

        let specs: [(r: CGFloat, width: CGFloat, dash: [CGFloat], speed: Double, alpha: Double)] = [
            (0.86, 4, [radius * 0.55, radius * 0.35],  28, 0.85),
            (0.78, 7, [radius * 0.16, radius * 0.10], -40, 0.65),
            (0.44, 5, [radius * 0.30, radius * 0.22],  18, 0.90),
        ]

        for spec in specs {
            let r = radius * spec.r
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            let style = StrokeStyle(lineWidth: spec.width,
                                    lineCap: .butt,
                                    dash: spec.dash,
                                    dashPhase: CGFloat(t * spec.speed))
            ring.stroke(Path(ellipseIn: rect),
                        with: .color(Theme.arc.opacity(spec.alpha)),
                        style: style)
        }
    }

    /// The classic ten copper-coil windows around the core, slowly rotating.
    private func drawCoilSegments(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                                  t: Double, pulse: Double) {
        var ring = ctx
        ring.addFilter(.shadow(color: Theme.arcBright.opacity(0.7), radius: 12))

        let r = radius * 0.62
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        let circumference = 2 * .pi * r
        let segment = circumference / 10
        let style = StrokeStyle(lineWidth: radius * 0.17,
                                lineCap: .butt,
                                dash: [segment * 0.68, segment * 0.32],
                                dashPhase: CGFloat(t * 6))
        ring.stroke(Path(ellipseIn: rect),
                    with: .color(Theme.arcBright.opacity(0.5 + 0.4 * pulse)),
                    style: style)
    }

    private func drawCore(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat, pulse: Double) {
        var core = ctx
        core.addFilter(.shadow(color: Theme.arcBright.opacity(0.9), radius: 24))

        let r = radius * (0.30 + 0.022 * pulse)
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        core.fill(Path(ellipseIn: rect),
                  with: .radialGradient(
                    Gradient(colors: [
                        Color.white,
                        Theme.arcBright,
                        Theme.arc.opacity(0.85),
                        Theme.arc.opacity(0.0),
                    ]),
                    center: center, startRadius: 0, endRadius: r))

        // Hard inner ring around the white-hot center.
        let r2 = radius * 0.31
        let rect2 = CGRect(x: center.x - r2, y: center.y - r2, width: r2 * 2, height: r2 * 2)
        core.stroke(Path(ellipseIn: rect2),
                    with: .color(Theme.arcBright.opacity(0.55 + 0.4 * pulse)),
                    lineWidth: 2)
    }
}
