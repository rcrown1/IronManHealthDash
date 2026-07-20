//
//  EKGWaveformView.swift
//  StarkHUD — a synthesized PQRST cardiac trace scrolling across a
//  monitor grid, its rate locked to the wearer's live BPM.
//

import SwiftUI

struct EKGWaveformView: View {
    var bpm: Double
    var color: Color = Theme.arc

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                drawGrid(ctx, size: size)
                drawTrace(ctx, size: size, t: t)
            }
        }
    }

    // MARK: Grid

    private func drawGrid(_ ctx: GraphicsContext, size: CGSize) {
        var grid = Path()
        let step: CGFloat = 42
        var x: CGFloat = 0
        while x <= size.width {
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        var y: CGFloat = 0
        while y <= size.height {
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
            y += step
        }
        ctx.stroke(grid, with: .color(Theme.arcDim.opacity(0.22)), lineWidth: 1)
    }

    // MARK: Trace

    /// Idealized PQRST complex over one normalized beat (0..1), range roughly -0.3..1.
    private func pqrst(_ p: Double) -> Double {
        func bump(_ c: Double, _ w: Double, _ a: Double) -> Double {
            let d = (p - c) / w
            return a * exp(-d * d)
        }
        return bump(0.16, 0.030, 0.14)     // P
             + bump(0.28, 0.009, -0.10)    // Q
             + bump(0.305, 0.007, 1.00)    // R
             + bump(0.33, 0.010, -0.24)    // S
             + bump(0.52, 0.045, 0.30)     // T
    }

    private func drawTrace(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let beat = 60.0 / max(bpm, 30)
        let pxPerSecond = 220.0
        let midY = size.height * 0.58
        let amplitude = size.height * 0.36

        var path = Path()
        var x: CGFloat = 0
        let stepX: CGFloat = 3
        while x <= size.width {
            let tau = t - Double(size.width - x) / pxPerSecond
            let phase = (tau / beat).truncatingRemainder(dividingBy: 1)
            let y = midY - CGFloat(pqrst(phase < 0 ? phase + 1 : phase)) * amplitude
            if x == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
            x += stepX
        }

        // Trail fades in from the left; the leading edge burns bright.
        var glow = ctx
        glow.addFilter(.shadow(color: color.opacity(0.9), radius: 9))
        glow.stroke(path,
                    with: .linearGradient(
                        Gradient(colors: [color.opacity(0.0), color.opacity(0.35), color]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: size.width, y: 0)),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))

        // Leading dot.
        let leadPhase = (t / beat).truncatingRemainder(dividingBy: 1)
        let leadY = midY - CGFloat(pqrst(leadPhase)) * amplitude
        let dot = CGRect(x: size.width - 5, y: leadY - 5, width: 10, height: 10)
        var dotCtx = ctx
        dotCtx.addFilter(.shadow(color: color, radius: 14))
        dotCtx.fill(Path(ellipseIn: dot), with: .color(.white))
    }
}
