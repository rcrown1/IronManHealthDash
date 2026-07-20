//
//  StarkHUDApp.swift
//  StarkHUD — Tony Stark's workshop biometric display for Apple TV.
//

import SwiftUI

@main
@MainActor
struct StarkHUDApp: App {
    @State private var store = MetricStore()
    @State private var receiver: HUDLinkReceiver?
    @State private var demoEngine: DemoDataEngine?

    var body: some Scene {
        WindowGroup {
            HUDRootView()
                .environment(store)
                .onAppear {
                    guard receiver == nil else { return }
                    let link = HUDLinkReceiver(store: store)
                    link.start()
                    receiver = link

                    let demo = DemoDataEngine(store: store)
                    demo.start()
                    demoEngine = demo
                }
        }
    }
}
