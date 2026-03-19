//
//  SwiftUIPlayer.swift
//  SwiftUIPlayer
//
//  Copyright © 2024 Brightcove, Inc. All rights reserved.
//

import SwiftUI


@main
struct SwiftUIPlayer: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    @StateObject private var router = DeepLinkRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(router)
                .onOpenURL { url in
                    router.handle(url: url)
                }
        }
    }

}
