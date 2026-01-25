//
//  AVIMAVideoItem.swift
//  SwiftUIPlayer
//
//  A model representing a video with IMA ad integration.
//

import Foundation
import BrightcovePlayerSDK

/// Represents a video item with IMA (Interactive Media Ads) configuration.
///
/// This model contains all necessary information for video playback including
/// the video content, ad configuration, and metadata for display purposes.
///
/// - Note: This model implements custom decoding for resilient parsing following
///         CLAUDE.md standards for API model handling.
struct AVIMAVideoItem: Identifiable, Equatable {

    // MARK: - Properties

    /// Unique identifier for the video
    let id: String

    /// Display name of the video
    let name: String

    /// Detailed description of the video content
    let description: String

    /// URL string for the video thumbnail image
    let thumbnailURL: String?

    /// Duration of the video in seconds
    let duration: TimeInterval?

    /// IMA ad tag URL for ad serving
    let adTagURL: String

    /// The underlying Brightcove video object
    let video: BCOVVideo

    // MARK: - Initialization

    /// Creates an IMA video item with all required properties.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for the video
    ///   - name: Display name
    ///   - description: Video description
    ///   - thumbnailURL: Optional thumbnail URL string
    ///   - duration: Optional video duration in seconds
    ///   - adTagURL: IMA ad tag URL for ad insertion
    ///   - video: Brightcove video object
    init(
        id: String,
        name: String,
        description: String = "",
        thumbnailURL: String? = nil,
        duration: TimeInterval? = nil,
        adTagURL: String,
        video: BCOVVideo
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.thumbnailURL = thumbnailURL
        self.duration = duration
        self.adTagURL = adTagURL
        self.video = video
    }

    // MARK: - Equatable

    static func == (lhs: AVIMAVideoItem, rhs: AVIMAVideoItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Sample Data

extension AVIMAVideoItem {

    /// Sample video items for testing and previews.
    ///
    /// - Note: Uses Google IMA sample ad tags for demonstration purposes.
    static let samples: [AVIMAVideoItem] = [
        AVIMAVideoItem(
            id: "sample-1",
            name: "Sample Video with Pre-roll",
            description: "Demonstrates pre-roll ad playback before main content",
            thumbnailURL: nil,
            duration: 120,
            adTagURL: "https://pubads.g.doubleclick.net/gampad/ads?iu=/21775744923/external/single_ad_samples&sz=640x480&cust_params=sample_ct%3Dlinear&ciu_szs=300x250%2C728x90&gdfp_req=1&output=vast&unviewed_position_start=1&env=vp&impl=s&correlator=",
            video: BCOVVideo()
        ),
        AVIMAVideoItem(
            id: "sample-2",
            name: "Sample Video with Mid-roll",
            description: "Demonstrates mid-roll ad insertion at cue points",
            thumbnailURL: nil,
            duration: 180,
            adTagURL: "https://pubads.g.doubleclick.net/gampad/ads?iu=/21775744923/external/vmap_ad_samples&sz=640x480&cust_params=sample_ar%3Dpremidpostpod&ciu_szs=300x250&gdfp_req=1&ad_rule=1&output=vmap&unviewed_position_start=1&env=vp&impl=s&correlator=",
            video: BCOVVideo()
        ),
        AVIMAVideoItem(
            id: "sample-3",
            name: "Sample Video with Skippable Ads",
            description: "Demonstrates skippable ad functionality",
            thumbnailURL: nil,
            duration: 150,
            adTagURL: "https://pubads.g.doubleclick.net/gampad/ads?iu=/21775744923/external/single_ad_samples&sz=640x480&cust_params=sample_ct%3Dskippablelinear&ciu_szs=300x250%2C728x90&gdfp_req=1&output=vast&unviewed_position_start=1&env=vp&impl=s&correlator=",
            video: BCOVVideo()
        )
    ]
}
