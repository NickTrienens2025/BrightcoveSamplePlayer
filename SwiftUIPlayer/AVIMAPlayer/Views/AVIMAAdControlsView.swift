//
//  AVIMAAdControlsView.swift
//  SwiftUIPlayer
//
//  Dedicated controls for Ad playback.
//

import SwiftUI

/// Controls specifically for Ad playback mode.
///
/// Features:
/// - Right-aligned layout
/// - Optional mute button (default hidden)
/// - Skip button (when available)
/// - Play/Pause toggle
/// - No background gradient (handled by parent)
struct AVIMAAdControlsView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: AVIMAPlayerViewModel
    var showMute: Bool = false

    // MARK: - Body

    var body: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 24) {
                Spacer()
                
                if viewModel.canSkip {
                    skipButton
                }
                
                playPauseButton
                
                if showMute {
                    muteButton
                }
            }
            .font(.title2)
            .padding() // Add padding for safe edge spacing
        }
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
                .font(.system(size: 24)) // Smaller size
                .foregroundStyle(.white)
                .padding(12) // Padding for touch target and visual balance
                .background(
                    Circle()
                        .fill(.black.opacity(0.6)) // Faded black background
                )
        }
        .disabled(viewModel.isLoading)
    }

    private var muteButton: some View {
        Button {
            viewModel.toggleMute()
        } label: {
            Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
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
    }
}

#if DEBUG
struct AVIMAAdControlsView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            AVIMAAdControlsView(viewModel: AVIMAPlayerViewModel(), showMute: true)
                .padding()
        }
    }
}
#endif
