//
//  AVIMAAdControlsView.swift
//  SwiftUIPlayer
//
//  Dedicated controls for Ad playback.
//

import SwiftUI

/// Horizontal controls bar for Ad playback, designed to sit below the video surface.
///
/// Features:
/// - Horizontal bar layout (expand | ad progress | spacer | skip | play/pause)
/// - Optional expand button for embedded mode
/// - Ad progress text ("Ad 1 of 3")
/// - Skip button (when available)
/// - Play/Pause toggle
/// - Dark background bar
struct AVIMAAdControlsView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: AVIMAPlayerViewModel
    var onExpand: (() -> Void)? = nil

    // MARK: - Body

    var body: some View {
        HStack(spacing: 16) {
            // Expand button (embedded mode only)
            if let onExpand {
                ControlButton(
                    systemImage: "arrow.up.left.and.arrow.down.right",
                    size: 28,
                    showBackdrop: false,
                    accessibilityLabel: "Fullscreen",
                    identifier: AccessibilityID.Controls.expandButton,
                    action: onExpand
                )
            }

            // Ad progress text
            if let adProgress = viewModel.adProgress {
                Text("Ad \(adProgress.currentAdNumber) of \(adProgress.totalAds)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            if viewModel.canSkip {
                skipButton
            }

            playPauseButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black)
    }

    // MARK: - Components

    private var playPauseButton: some View {
        Button {
            if viewModel.isPlaying {
                viewModel.pause()
            } else {
                viewModel.play()
            }
        } label: {
            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(.white.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
    }

    private var skipButton: some View {
        Button {
            viewModel.skipAd()
        } label: {
            HStack(spacing: 4) {
                Text("Skip")
                    .font(.caption.weight(.semibold))
                Image(systemName: "forward.fill")
                    .font(.caption2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.2))
            )
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
struct AVIMAAdControlsView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            AVIMAAdControlsView(
                viewModel: AVIMAPlayerViewModel(),
                onExpand: { print("Expand") }
            )
        }
        .background(Color.gray)
    }
}
#endif
