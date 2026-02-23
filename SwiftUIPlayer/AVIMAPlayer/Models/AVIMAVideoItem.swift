//
//  AVIMAVideoItem.swift
//  SwiftUIPlayer
//
//  A model representing a video with IMA ad integration.
//

import CoreMedia
import Foundation
import BrightcovePlayerSDK

// MARK: - Ad Cue Point Model

/// Represents an ad insertion point during video playback.
///
/// Tracks both the position and whether the ad has already played
/// in the current session to support once-per-session midroll behavior.
struct AdCuePoint: Identifiable, Equatable {
    let id = UUID()

    /// Position in the video timeline (seconds)
    let position: TimeInterval

    /// Type of cue point
    let type: CuePointType

    /// Whether this cue point has already played in the current session
    var hasPlayed: Bool = false

    enum CuePointType: Equatable {
        /// Pre-roll ad (position == 0)
        case preRoll
        /// Mid-roll ad (0 < position < duration)
        case midRoll
    }

    /// Normalized position (0.0 to 1.0) relative to video duration.
    /// Returns nil if duration is unavailable, zero, or position exceeds duration.
    func normalizedPosition(forDuration duration: TimeInterval) -> Double? {
        guard duration > 0, position <= duration else { return nil }
        return position / duration
    }
}

/// Default IMA ad tag URL used for all videos.
///
/// **Configuration:** Pre-roll ad (plays before content starts)
/// - `unviewed_position_start=1` ensures the ad plays at the beginning
/// - `sample_ct=linear` specifies a linear (non-skippable by default) ad
///
/// This is a Google IMA sample ad tag. In production, replace with your actual
/// ad server URL from your ad network (e.g., Google Ad Manager, SpotX, etc.).
///
/// **Example production ad tags:**
/// - Google Ad Manager: `https://pubads.g.doubleclick.net/gampad/ads?iu=/YOUR_NETWORK_CODE/...`
/// - Custom VAST: `https://your-ad-server.com/vast?position=preroll`
let kDefaultIMAAdTagURL = "https://pubads.g.doubleclick.net/gampad/ads?iu=/21775744923/external/single_ad_samples&sz=640x480&cust_params=sample_ct%3Dlinear&ciu_szs=300x250%2C728x90&gdfp_req=1&output=vast&unviewed_position_start=1&env=vp&impl=s&correlator="

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

    /// Aspect ratio of the video (width / height)
    let aspectRatio: Double

    /// Midroll ad positions in seconds (empty = no midrolls)
    let midRollPositions: [TimeInterval]

    // MARK: - Initialization

    /// Creates an IMA video item with all required properties.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for the video
    ///   - name: Display name
    ///   - description: Video description
    ///   - thumbnailURL: Optional thumbnail URL string
    ///   - duration: Optional video duration in seconds
    ///   - adTagURL: IMA ad tag URL for ad insertion (defaults to kDefaultIMAAdTagURL)
    ///   - aspectRatio: Video aspect ratio (width/height), defaults to 16:9
    ///   - midRollPositions: Midroll ad positions in seconds (defaults to empty)
    ///   - video: Brightcove video object
    init(
        id: String,
        name: String,
        description: String = "",
        thumbnailURL: String? = nil,
        duration: TimeInterval? = nil,
        adTagURL: String = kDefaultIMAAdTagURL,
        aspectRatio: Double = 16.0/9.0,
        midRollPositions: [TimeInterval] = [],
        video: BCOVVideo
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.thumbnailURL = thumbnailURL
        self.duration = duration
        self.adTagURL = adTagURL
        self.aspectRatio = aspectRatio
        self.midRollPositions = midRollPositions
        self.video = video
    }

    /// Creates an IMA video item from a Brightcove video object.
    ///
    /// Extracts metadata from the BCOVVideo properties, adds pre-roll and midroll
    /// ad cue points, and uses the default ad tag.
    ///
    /// - Parameters:
    ///   - video: The Brightcove video object
    ///   - midRollPositions: Midroll ad positions in seconds (defaults to 180s = 3 minutes)
    /// - Returns: AVIMAVideoItem if video has required ID and name properties, nil otherwise
    static func from(video: BCOVVideo, midRollPositions: [TimeInterval] = [180]) -> AVIMAVideoItem? {
        guard let videoId = video.properties[BCOVVideo.PropertyKeyId] as? String,
              let videoName = video.properties[BCOVVideo.PropertyKeyName] as? String else {
            return nil
        }

        let description = video.properties[BCOVVideo.PropertyKeyDescription] as? String ?? ""

        // Extract thumbnail URL
        let thumbnailURL: String?
        if let poster = video.properties[BCOVVideo.PropertyKeyPoster] as? String {
            thumbnailURL = poster
        } else if let thumbnail = video.properties[BCOVVideo.PropertyKeyThumbnail] as? String {
            thumbnailURL = thumbnail
        } else {
            thumbnailURL = nil
        }

        // Extract duration
        let duration: TimeInterval?
        if let durationMs = video.properties[BCOVVideo.PropertyKeyDuration] as? NSNumber {
            duration = durationMs.doubleValue / 1000.0 // Convert from milliseconds to seconds
        } else {
            duration = nil
        }

        // Extract aspect ratio from video source
        let aspectRatio: Double = {
            if let frameWidth = video.properties["frame_width"] as? NSNumber,
               let frameHeight = video.properties["frame_height"] as? NSNumber {
                let w = frameWidth.doubleValue
                let h = frameHeight.doubleValue
                if h > 0 {
                    debugPrintWithTimestamp("📐 Video dimensions: \(w)x\(h), aspect ratio: \(w/h)")
                    return w / h
                }
            }
            debugPrintWithTimestamp("📐 No video dimensions found, using 16:9 default")
            return 16.0 / 9.0
        }()

        // Add pre-roll + midroll ad cue points
        let videoWithAds = addAdCuePoints(to: video, midRollPositions: midRollPositions)

        return AVIMAVideoItem(
            id: videoId,
            name: videoName,
            description: description,
            thumbnailURL: thumbnailURL,
            duration: duration,
            adTagURL: kDefaultIMAAdTagURL,
            aspectRatio: aspectRatio,
            midRollPositions: midRollPositions,
            video: videoWithAds
        )
    }

    /// Adds pre-roll and midroll ad cue points to a Brightcove video.
    ///
    /// Creates a cue point at position 0 (pre-roll) and at each midroll position.
    /// Avoids duplicating cue points that already exist on the video.
    ///
    /// - Parameters:
    ///   - video: The original BCOVVideo
    ///   - midRollPositions: Midroll positions in seconds
    /// - Returns: A new BCOVVideo with the ad cue points added
    private static func addAdCuePoints(to video: BCOVVideo, midRollPositions: [TimeInterval]) -> BCOVVideo {
        var cuePoints: [BCOVCuePoint] = [
            BCOVCuePoint(withType: "ad", position: CMTime.zero)
        ]

        for position in midRollPositions {
            cuePoints.append(
                BCOVCuePoint(
                    withType: "ad",
                    position: CMTime(seconds: position, preferredTimescale: 600)
                )
            )
        }

        // Merge with existing, avoiding duplicates
        let existing = (video.cuePoints?.array as? [BCOVCuePoint]) ?? []
        let existingPositions = Set(existing.map { $0.position.seconds })
        let newCuePoints = cuePoints.filter { !existingPositions.contains($0.position.seconds) }
        let allCuePoints = existing + newCuePoints

        let collection = BCOVCuePointCollection(withArray: allCuePoints)

        return video.update { mutableVideo in
            mutableVideo.cuePoints = collection
        }
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
    /// - Note: Uses Brightcove sample video URLs for actual playback.
    static let samples: [AVIMAVideoItem] = {
        // Sample video URLs from Brightcove
        let sampleVideoURL = "https://solutions.brightcove.com/bcls/assets/videos/Great_Horned_Owl.mp4"

        // Create BCOVSource for the sample video
        guard let videoURL = URL(string: sampleVideoURL) else {
            return []
        }

        let source = BCOVSource(withURL: videoURL, deliveryMethod: nil, properties: nil)

        // Create BCOVVideo objects
        let video1 = BCOVVideo(withSource: source, cuePoints: BCOVCuePointCollection(withArray: []), properties: [
            "id": "sample-1",
            "name": "Sample Video with Pre-roll"
        ])

        let video2 = BCOVVideo(withSource: source, cuePoints: BCOVCuePointCollection(withArray: []), properties: [
            "id": "sample-2",
            "name": "Sample Video with Mid-roll"
        ])

        let video3 = BCOVVideo(withSource: source, cuePoints: BCOVCuePointCollection(withArray: []), properties: [
            "id": "sample-3",
            "name": "Sample Video with Skippable Ads"
        ])

        return [
            AVIMAVideoItem(
                id: "sample-1",
                name: "Sample Video with Pre-roll",
                description: "Demonstrates pre-roll ad playback before main content",
                thumbnailURL: nil,
                duration: 120,
                video: video1
            ),
            AVIMAVideoItem(
                id: "sample-2",
                name: "Sample Video with Mid-roll",
                description: "Demonstrates mid-roll ad insertion at cue points",
                thumbnailURL: nil,
                duration: 300,
                midRollPositions: [180],
                video: video2
            ),
            AVIMAVideoItem(
                id: "sample-3",
                name: "Sample Video with Skippable Ads",
                description: "Demonstrates skippable ad functionality",
                thumbnailURL: nil,
                duration: 150,
                video: video3
            )
        ]
    }()
}
