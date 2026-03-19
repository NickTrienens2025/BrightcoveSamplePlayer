//
//  DeepLinkRouter.swift
//  SwiftUIPlayer
//
//  Copyright © 2024 Brightcove, Inc. All rights reserved.
//

import Foundation


// MARK: - DeepLinkCommand

enum DeepLinkCommand: Equatable {
    case navigateToVideo(videoIndex: Int, controlType: ControlType)
    case enterFullscreen
    case seek(time: TimeInterval)
}


// MARK: - DeepLinkRouter

/// Parses `swiftuiplayer://` deep link URLs into typed `DeepLinkCommand` values.
///
/// **Supported URL schemes:**
/// - `swiftuiplayer://navigate?tab=videos&controlType=BCOV%20IMA%20ViewController&videoIndex=0`
/// - `swiftuiplayer://player/fullscreen`
/// - `swiftuiplayer://player/seek?time=30`
@MainActor
final class DeepLinkRouter: ObservableObject {

    @Published var pendingCommand: DeepLinkCommand?

    func handle(url: URL) {
        guard url.scheme == "swiftuiplayer" else { return }

        switch url.host {
        case "navigate":
            pendingCommand = parseNavigateCommand(from: url)
        case "player":
            pendingCommand = parsePlayerCommand(from: url)
        default:
            break
        }
    }

    // MARK: - Private Helpers

    private func parseNavigateCommand(from url: URL) -> DeepLinkCommand? {
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems ?? []

        guard let videoIndexString = queryItems.value(for: "videoIndex"),
              let videoIndex = Int(videoIndexString) else {
            return nil
        }

        let controlType = resolveControlType(from: queryItems.value(for: "controlType"))
        return .navigateToVideo(videoIndex: videoIndex, controlType: controlType)
    }

    private func parsePlayerCommand(from url: URL) -> DeepLinkCommand? {
        // url.path returns "/fullscreen" or "/seek" — drop the leading slash
        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path

        switch path {
        case "fullscreen":
            return .enterFullscreen
        case "seek":
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems ?? []
            guard let timeString = queryItems.value(for: "time"),
                  let time = TimeInterval(timeString) else {
                return nil
            }
            return .seek(time: time)
        default:
            return nil
        }
    }

    private func resolveControlType(from rawValue: String?) -> ControlType {
        guard let rawValue else { return .bcovViewController }

        // Exact match first
        if let exact = ControlType(rawValue: rawValue) {
            return exact
        }

        // Case-insensitive contains fallback
        let lower = rawValue.lowercased()
        if let match = ControlType.allCases.first(where: {
            $0.rawValue.lowercased().contains(lower) || lower.contains($0.rawValue.lowercased())
        }) {
            return match
        }

        return .bcovViewController
    }
}


// MARK: - [URLQueryItem] Helpers

private extension Array where Element == URLQueryItem {
    func value(for name: String) -> String? {
        first(where: { $0.name == name })?.value
    }
}
