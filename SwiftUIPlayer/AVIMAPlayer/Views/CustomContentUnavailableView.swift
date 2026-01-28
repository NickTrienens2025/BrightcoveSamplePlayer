//
//  CustomContentUnavailableView.swift
//  SwiftUIPlayer
//
//  iOS 16 compatible alternative to ContentUnavailableView.
//

import SwiftUI

/// Custom content unavailable view for iOS 16 compatibility.
///
/// Provides similar functionality to iOS 17's ContentUnavailableView
/// but works on iOS 16.0+.
///
/// **Features:**
/// - Title with optional system image
/// - Description text
/// - Optional action buttons
/// - Centered layout with consistent spacing
struct CustomContentUnavailableView<Actions: View>: View {

    // MARK: - Properties

    let title: String
    let systemImage: String
    let description: String?
    let actions: Actions

    // MARK: - Initialization

    /// Creates a content unavailable view with all components.
    ///
    /// - Parameters:
    ///   - title: Main title text
    ///   - systemImage: SF Symbol name for icon
    ///   - description: Optional description text
    ///   - actions: Optional action buttons
    init(
        _ title: String,
        systemImage: String,
        description: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actions = actions()
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // Icon
            Image(systemName: systemImage)
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            // Title
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            // Description
            if let description = description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Actions
            actions
                .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Convenience Initializers

extension CustomContentUnavailableView where Actions == EmptyView {

    /// Creates a content unavailable view without actions.
    ///
    /// - Parameters:
    ///   - title: Main title text
    ///   - systemImage: SF Symbol name for icon
    ///   - description: Optional description text
    init(
        _ title: String,
        systemImage: String,
        description: String? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actions = EmptyView()
    }
}

// MARK: - Preview

#if DEBUG
struct CustomContentUnavailableView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // With action
            CustomContentUnavailableView(
                "Unable to Load Videos",
                systemImage: "exclamationmark.triangle",
                description: "Check your internet connection and try again."
            ) {
                Button("Retry") {
                    debugPrintWithTimestamp("Retry tapped")
                }
                .buttonStyle(.borderedProminent)
            }

            // Without action
            CustomContentUnavailableView(
                "No Videos",
                systemImage: "video.slash",
                description: "There are no videos available at this time."
            )
        }
    }
}
#endif
