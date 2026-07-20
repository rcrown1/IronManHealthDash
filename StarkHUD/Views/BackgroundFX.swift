//
//  BackgroundFX.swift
//  StarkHUD — the workshop atmosphere: blueprint grid, drifting motes,
//  a slow scanning band, and an edge vignette.
//

import SwiftUI

struct BackgroundFX: View {
    var body: some View {
        ZStack {
            Theme.bg

            // Blueprint grid (static — drawn once).
            Canvas { ctx, size in
                var grid = Path()
                let step: CGFloat = 96
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
                ctx.stroke(grid, with: .color(Theme.arcDim.opacity(0.10)), lineWidth: 1)
            }

            // Center glow, as if the reactor lights the room.
            RadialGradient(colors: [Theme.arc.opacity(0.055), .clear],
                           center: .center, startRadius: 60, endRadius: 900)

            ParticleField()

            // Vignette.
            RadialGradient(colors: [.clear, .black.opacity(0.55)],
                           center: .center, startRadius: 500, endRadius: 1250)
        }
        .ignoresSafeArea()
    }
}

/// Slow-drifting luminous motes plus a horizontal scanning band.
private struct ParticleField: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate

                for i in 0..<56 {
                    let seed = Double(i)
                    let sx = fract(sin(seed * 12.9898) * 43758.5453)
                    let sy = fract(sin(seed * 78.233) * 12543.1234)
                    let speed = 5.0 + fract(sin(seed * 3.7) * 999) * 14.0
                    let x = sx * size.width + sin(t * 0.25 + seed) * 22
                    let y = fract(sy - t * speed / 3200) * size.height
                    let twinkle = 0.25 + 0.5 * (0.5 + 0.5 * sin(t * (0.8 + fract(seed * 0.13)) + seed * 7))
                    let r = 1.2 + fract(seed * 0.31) * 2.2
                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(Theme.arc.opacity(twinkle * 0.4)))
                }

                // Scanning band sweeping top to bottom every ~11 seconds.
                let bandY = fract(t / 11.0) * (size.height + 300) - 150
                let band = CGRect(x: 0, y: bandY, width: size.width, height: 150)
                ctx.fill(Path(band),
                         with: .linearGradient(
                            Gradient(colors: [Theme.arc.opacity(0.0),
                                              Theme.arc.opacity(0.045),
                                              Theme.arc.opacity(0.0)]),
                            startPoint: CGPoint(x: 0, y: bandY),
                            endPoint: CGPoint(x: 0, y: bandY + 150)))
            }
        }
        .allowsHitTesting(false)
    }

    private func fract(_ v: Double) -> Double {
        v - floor(v)
    }
}
