//
//  ContentView.swift
//  SwiftUIPlayer
//
//  Copyright © 2024 Brightcove, Inc. All rights reserved.
//

import SwiftUI


struct ContentView: View {

    @State
    fileprivate var selection = Tab.videos

    @StateObject
    fileprivate var playerModel = PlayerModel()

    @EnvironmentObject
    var router: DeepLinkRouter

    enum Tab {
        case videos
        case imaVideos
    }

    var body: some View {
        TabView(selection: $selection) {
            VideoListView(playerModel: playerModel)
                .tabItem {
                    Label("Videos", systemImage: "list.triangle")
                }
                .tag(Tab.videos)

            AVIMAPlayerListView()
                .tabItem {
                    Label("AVIMA Player", systemImage: "play.rectangle.fill")
                }
                .tag(Tab.imaVideos)
        }
        .onChange(of: router.pendingCommand) { _, command in
            guard let command else { return }
            handleCommand(command)
        }
    }

    private func handleCommand(_ command: DeepLinkCommand) {
        switch command {
        case .navigateToVideo:
            selection = .videos
            // VideoListView handles the rest
        case .enterFullscreen:
            playerModel.enterFullscreen()
            router.pendingCommand = nil
        case .seek(let time):
            playerModel.seek(to: time)
            router.pendingCommand = nil
        }
    }
}


// MARK: -

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(DeepLinkRouter())
    }
}
#endif
