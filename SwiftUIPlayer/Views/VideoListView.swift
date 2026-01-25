//
//  VideoListView.swift
//  SwiftUIPlayer
//
//  Copyright © 2024 Brightcove, Inc. All rights reserved.
//

import SwiftUI


/// Player control type options for demonstrating different integration patterns.
///
/// This enum demonstrates four different approaches for integrating video players in SwiftUI:
///
/// **BCOV View** - Uses BCOVPUIPlayerView wrapped in UIViewRepresentable
/// - Best for: Simple SwiftUI integration when you don't need IMA ads
/// - Pattern: UIViewRepresentable wrapping a UIView
/// - Limitation: May have view controller hierarchy issues with IMA ads
///
/// **BCOV ViewController** - Uses BCOVPUIPlayerViewController wrapped in UIViewControllerRepresentable
/// - Best for: SwiftUI apps that require proper view controller hierarchy
/// - Pattern: UIViewControllerRepresentable wrapping a UIViewController
/// - Benefit: Provides proper parent view controller for modals and presentations
///
/// **BCOV IMA ViewController** - Uses BCOVPUIIMAPlayerViewController with IMA ads integration
/// - Best for: SwiftUI apps that need Google IMA ads
/// - Pattern: UIViewControllerRepresentable wrapping a custom BCOVPUIPlayerViewController subclass
/// - Benefit: Full IMA ads support with pre-roll, mid-roll, and post-roll ads
/// - Note: Recommended approach for production apps using ads
///
/// **AVPlayerViewController** - Uses Apple's native AVPlayerViewController
/// - Best for: Simple playback with Apple's native UI
/// - Pattern: UIViewControllerRepresentable wrapping AVPlayerViewController
/// - Limitation: No Brightcove-specific features (analytics, ads, etc.)
enum ControlType: String, Equatable, CaseIterable, Identifiable {
    case bcov = "BCOV View"
    case bcovViewController = "BCOV ViewController"
    case bcovIMAViewController = "BCOV IMA ViewController"
    case native = "AVPlayerViewController"

    var id: String { rawValue }
}


struct VideoListView: View {

    @StateObject
    fileprivate var playlistModel = PlaylistModel()

    @ObservedObject
    var playerModel: PlayerModel

    @State
    fileprivate var controlType: ControlType = .bcov

    @State
    fileprivate var isShowingDetailView = false

    var body: some View {
        NavigationStack {
            VStack {
                VStack(alignment: .leading) {
                    Text("Control Type")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Picker("ControlType", selection: $controlType) {
                        ForEach(ControlType.allCases) { type in
                            Text(type.rawValue)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding()

                List(playlistModel.videoListItems) { listItem in
                    NavigationLink {
                        VideoDetailView(playerModel: playerModel,
                                        videoItem: listItem,
                                        controlType: controlType)
                        .navigationTitle(listItem.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .navigationBarBackButtonHidden(true)
                        .statusBarHidden(playerModel.fullscreenEnabled)
                        .toolbar(playerModel.fullscreenEnabled ? .hidden : .visible, for: .tabBar)
                        .toolbar(playerModel.fullscreenEnabled ? .hidden : .visible, for: .navigationBar)
                    } label: {
                        VideoListRowView(video: listItem.video)
                    }
                }
                .listStyle(.plain)
            }
            .navigationBarTitleDisplayMode(.large)
            .navigationTitle("Videos")
        }
    }

}


// MARK: -

#if DEBUG
struct VideoListView_Previews: PreviewProvider {
    static var previews: some View {
        VideoListView(playerModel: PlayerModel())
    }
}
#endif
