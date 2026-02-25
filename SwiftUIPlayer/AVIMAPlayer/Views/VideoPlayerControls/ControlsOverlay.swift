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
            // Aspect-fit: use the largest rect that fits inside the container
            let containerWidth = geometry.size.width
            let containerHeight = geometry.size.height

            let widthBasedHeight = containerWidth / aspectRatio
            let heightBasedWidth = containerHeight * aspectRatio

            let videoWidth: CGFloat = widthBasedHeight <= containerHeight
                ? containerWidth        // Width-constrained (letterbox)
                : heightBasedWidth      // Height-constrained (pillarbox)

            let videoHeight: CGFloat = widthBasedHeight <= containerHeight
                ? widthBasedHeight
                : containerHeight

            content()
                .frame(width: videoWidth, height: videoHeight)
                .position(x: containerWidth / 2, y: containerHeight / 2)
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
