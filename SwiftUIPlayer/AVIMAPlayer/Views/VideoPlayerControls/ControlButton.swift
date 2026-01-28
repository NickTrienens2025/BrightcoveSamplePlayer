//
//  ControlButton.swift
//  SwiftUIPlayer
//
//  Reusable control button with consistent styling for video player controls.
//

import SwiftUI

/// Reusable control button with consistent styling
///
/// **Features:**
/// - System image support
/// - Optional semi-transparent backdrop
/// - Configurable size and color
/// - Accessibility labels built-in
///
/// **Usage:**
/// ```swift
/// ControlButton(
///     systemImage: "play.fill",
///     size: 44,
///     accessibilityLabel: "Play"
/// ) {
///     viewModel.play()
/// }
/// ```
struct ControlButton: View {

    // MARK: - Properties

    let systemImage: String
    let size: CGFloat
    let color: Color
    let showBackdrop: Bool
    let accessibilityLabel: String
    let action: () -> Void

    // MARK: - Initialization

    init(
        systemImage: String,
        size: CGFloat = 44,
        color: Color = .white,
        showBackdrop: Bool = true,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.size = size
        self.color = color
        self.showBackdrop = showBackdrop
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    // MARK: - Body

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.5))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(
                    Group {
                        if showBackdrop {
                            Circle()
                                .fill(.black.opacity(0.7))
                        }
                    }
                )
                .shadow(color: showBackdrop ? .black.opacity(0.5) : .clear, radius: 8)
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Preview

#if DEBUG
struct ControlButton_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 32) {
                // Large play button
                ControlButton(
                    systemImage: "play.fill",
                    size: 60,
                    accessibilityLabel: "Play"
                ) {
                    print("Play tapped")
                }

                // Medium pause button
                ControlButton(
                    systemImage: "pause.fill",
                    size: 44,
                    accessibilityLabel: "Pause"
                ) {
                    print("Pause tapped")
                }

                // Small mute button
                ControlButton(
                    systemImage: "speaker.slash.fill",
                    size: 32,
                    accessibilityLabel: "Mute"
                ) {
                    print("Mute tapped")
                }

                // Button without backdrop
                ControlButton(
                    systemImage: "xmark",
                    size: 24,
                    showBackdrop: false,
                    accessibilityLabel: "Close"
                ) {
                    print("Close tapped")
                }
            }
        }
        .previewDisplayName("Control Buttons")
    }
}
#endif
