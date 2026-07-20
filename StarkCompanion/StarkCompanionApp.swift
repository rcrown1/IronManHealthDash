//
//  StarkCompanionApp.swift
//  StarkCompanion — streams HealthKit telemetry to the workshop display.
//

import SwiftUI

@main
@MainActor
struct StarkCompanionApp: App {
    @State private var model = CompanionViewModel()

    var body: some Scene {
        WindowGroup {
            CompanionRootView()
                .environment(model)
        }
    }
}
