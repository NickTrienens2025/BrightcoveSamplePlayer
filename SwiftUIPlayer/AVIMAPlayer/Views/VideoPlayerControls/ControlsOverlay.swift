//
//  ControlsOverlay.swift
//  SwiftUIPlayer
//
//  Constrains video player controls to match video aspect ratio.
//  Prevents controls from extending into black letterbox bars.
//

import SwiftUI

/// Constrains controls to video aspect ratio area
///
/// **Purpose:**
/// - Prevents controls from extending into black bars (letterboxing/pillarboxing)
/// - Matches video rendering area exactly
/// - Uses GeometryReader for responsive layout
///
/// **Usage:**
/// ```swift
/// ControlsOverlay(aspectRatio: 16/9) {
///     VideoPlayerControlsView(...)
/// }
/// ```
struct ControlsOverlay<Content: View>: View {

    // MARK: - Properties

    /// Video aspect ratio (width / height)
    let aspectRatio: Double

    /// Controls content to display
    let content: () -> Content

    // MARK: - Initialization

    init(aspectRatio: Double, @ViewBuilder content: @escaping () -> Content) {
        self.aspectRatio = aspectRatio
        self.content = content
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            // Calculate video area dimensions
            let videoWidth = geometry.size.width
            let videoHeight = videoWidth / aspectRatio

            content()
                .frame(width: videoWidth, height: videoHeight)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ControlsOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ControlsOverlay(aspectRatio: 16/9) {
                VStack {
                    Text("Top")
                        .foregroundStyle(.white)
                        .padding()
                        .background(Color.red.opacity(0.5))

                    Spacer()

                    Text("Center")
                        .foregroundStyle(.white)
                        .padding()
                        .background(Color.green.opacity(0.5))

                    Spacer()

                    Text("Bottom")
                        .foregroundStyle(.white)
                        .padding()
                        .background(Color.blue.opacity(0.5))
                }
            }
        }
        .previewDisplayName("16:9 Overlay")
    }
}
#endif
