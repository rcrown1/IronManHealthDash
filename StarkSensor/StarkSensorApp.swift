//
//  StarkSensorApp.swift
//  StarkSensor — Apple Watch heart-rate streamer for the Stark HUD.
//

import SwiftUI

@main
@MainActor
struct StarkSensorApp: App {
    @State private var streamer = HeartRateStreamer()

    var body: some Scene {
        WindowGroup {
            SensorRootView()
                .environment(streamer)
        }
    }
}
