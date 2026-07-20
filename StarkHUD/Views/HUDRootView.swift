//
//  HUDRootView.swift
//  StarkHUD — orchestrates the constantly shifting display.
//
//  Scenes auto-cycle every 22 seconds. Siri Remote: swipe left/right to
//  change scenes manually, play/pause to freeze/resume auto-cycling.
//

import SwiftUI

struct HUDRootView: View {
    @Environment(MetricStore.self) private var store
    @State private var scene: HUDScene = .arcCore
    @State private var autoCycle = true

    var body: some View {
        ZStack {
            BackgroundFX()

            VStack(spacing: 24) {
                HUDHeader(sceneTitle: scene.title + (autoCycle ? "" : "  ⏸"))

                sceneBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                TickerView()
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 44)

            CornerBrackets()
                .padding(28)
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left:
                changeScene(to: scene.previous)
            case .right:
                changeScene(to: scene.next)
            default:
                break
            }
        }
        .onPlayPauseCommand {
            autoCycle.toggle()
        }
        .onReceive(Timer.publish(every: 22, on: .main, in: .common).autoconnect()) { _ in
            if autoCycle {
                changeScene(to: scene.next)
            }
        }
    }

    @ViewBuilder
    private var sceneBody: some View {
        Group {
            switch scene {
            case .arcCore: ArcCoreScene()
            case .vitals: VitalsScene()
            case .power: PowerScene()
            case .recharge: RechargeScene()
            case .combatLog: CombatLogScene()
            case .mobility: MobilityScene()
            case .diagnostics: DiagnosticsScene()
            }
        }
        .id(scene)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 1.04)),
            removal: .opacity.combined(with: .scale(scale: 0.97))))
    }

    private func changeScene(to newScene: HUDScene) {
        withAnimation(.easeInOut(duration: 1.1)) {
            scene = newScene
        }
    }
}
