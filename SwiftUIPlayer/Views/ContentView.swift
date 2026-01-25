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

            IMAPlayerListView()
                .tabItem {
                    Label("IMA Player", systemImage: "play.rectangle.fill")
                }
                .tag(Tab.imaVideos)
        }
    }
}


// MARK: -

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
