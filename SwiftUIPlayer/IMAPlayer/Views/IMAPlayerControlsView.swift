//
//  IMAPlayerControlsView.swift
//  SwiftUIPlayer
//
//  Unified player controls that adapt to playback mode (main video vs advertisement).
//

import SwiftUI

/// Unified playback controls that adapt to current playback mode.
///
/// **Control Behavior:**
/// - **During Main Video:** Full controls (play/pause, seek, mute)
/// - **During Ads:** Limited controls (play/pause, mute only)
/// - **Skip Button:** Only shown for skippable ads
///
/// **Design:**
/// Uses consistent UI in both modes with controls dynamically enabled/disabled
/// based on playback mode, following CLAUDE.md principles for clear user feedback.
struct IMAPlayerControlsView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: IMAPlayerViewModel

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            // Progress and time display
            progressSection

            // Playback controls
            controlsSection

            // Ad info banner (shown during ads)
            if viewModel.playbackMode == .advertisement {
                adInfoBanner
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Progress Section

    @ViewBuilder
    private var progressSection: some View {
        VStack(spacing: 8) {
            // Time labels
            HStack {
                Text(formatTime(viewModel.currentTime))
                    .font(.caption)
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Spacer()

                Text(formatTime(viewModel.duration))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
            }

            // Progress slider
            if viewModel.canSeek {
                Slider(
                    value: seekBinding,
                    in: 0...max(viewModel.duration, 1)
                )
                .tint(.white)
            } else {
                // Non-interactive progress bar for ads
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(0.3))
                            .frame(height: 4)

                        // Progress fill
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white)
                            .frame(
                                width: geometry.size.width * viewModel.playbackProgress,
                                height: 4
                            )
                    }
                }
                .frame(height: 4)
            }
        }
    }

    // MARK: - Controls Section

    @ViewBuilder
    private var controlsSection: some View {
        HStack(spacing: 24) {
            // Skip button (only for skippable ads)
            if viewModel.canSkip && viewModel.playbackMode == .advertisement {
                skipButton
            }

            Spacer()

            // Play/Pause button
            playPauseButton

            Spacer()

            // Mute button
            muteButton
        }
        .font(.title2)
    }

    // MARK: - Play/Pause Button

    @ViewBuilder
    private var playPauseButton: some View {
        Button {
            if viewModel.isPlaying {
                viewModel.pause()
            } else {
                viewModel.play()
            }
        } label: {
            Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.white)
        }
        .disabled(viewModel.isLoading)
    }

    // MARK: - Mute Button

    @ViewBuilder
    private var muteButton: some View {
        Button {
            viewModel.toggleMute()
        } label: {
            Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
    }

    // MARK: - Skip Button

    @ViewBuilder
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

    // MARK: - Ad Info Banner

    @ViewBuilder
    private var adInfoBanner: some View {
        if let adProgress = viewModel.adProgress {
            HStack(spacing: 12) {
                // Ad indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(.yellow)
                        .frame(width: 8, height: 8)

                    Text("Ad")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                }

                // Ad position (e.g., "1 of 3")
                Text("\(adProgress.currentAdNumber) of \(adProgress.totalAds)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                // Remaining time
                if !adProgress.isSkippable {
                    Text("\(Int(adProgress.duration - adProgress.currentTime))s")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.black.opacity(0.6))
            )
        }
    }

    // MARK: - Helpers

    /// Creates a binding for the seek slider.
    private var seekBinding: Binding<Double> {
        Binding(
            get: { viewModel.currentTime },
            set: { newValue in
                viewModel.seek(to: newValue)
            }
        )
    }

    /// Formats time interval as MM:SS.
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time >= 0 else { return "0:00" }

        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#if DEBUG
struct IMAPlayerControlsView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack {
                Spacer()

                IMAPlayerControlsView(viewModel: IMAPlayerViewModel())
            }
        }
    }
}
#endif
