//
//  AVIMAVideoItem.swift
//  SwiftUIPlayer
//
//  A model representing a video with IMA ad integration.
//

import Foundation
import BrightcovePlayerSDK

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
    ///   - video: Brightcove video object
    init(
        id: String,
        name: String,
        description: String = "",
        thumbnailURL: String? = nil,
        duration: TimeInterval? = nil,
        adTagURL: String = kDefaultIMAAdTagURL,
        aspectRatio: Double = 16.0/9.0,
        video: BCOVVideo
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.thumbnailURL = thumbnailURL
        self.duration = duration
        self.adTagURL = adTagURL
        self.aspectRatio = aspectRatio
        self.video = video
    }

    /// Creates an IMA video item from a Brightcove video object.
    ///
    /// Extracts metadata from the BCOVVideo properties, adds pre-roll ad cue points,
    /// and uses the default ad tag.
    ///
    /// - Parameter video: The Brightcove video object
    /// - Returns: AVIMAVideoItem if video has required ID and name properties, nil otherwise
    static func from(video: BCOVVideo) -> AVIMAVideoItem? {
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
            // Try to get dimensions from the video properties
            // Brightcove stores frame width/height in the properties
            if let frameWidth = video.properties["frame_width"] as? NSNumber,
               let frameHeight = video.properties["frame_height"] as? NSNumber {
                let w = frameWidth.doubleValue
                let h = frameHeight.doubleValue
                if h > 0 {
                    debugPrintWithTimestamp("📐 Video dimensions: \(w)x\(h), aspect ratio: \(w/h)")
                    return w / h
                }
            }

            // Fallback to 16:9 if dimensions not available
            debugPrintWithTimestamp("📐 No video dimensions found, using 16:9 default")
            return 16.0 / 9.0
        }()

        // Add pre-roll ad cue point at position 0 (before content starts)
        let videoWithAds = addPreRollCuePoint(to: video)

        return AVIMAVideoItem(
            id: videoId,
            name: videoName,
            description: description,
            thumbnailURL: thumbnailURL,
            duration: duration,
            adTagURL: kDefaultIMAAdTagURL,
            aspectRatio: aspectRatio,
            video: videoWithAds
        )
    }

    /// Adds a pre-roll ad cue point to a Brightcove video.
    ///
    /// This creates a cue point at position 0 (before the content starts)
    /// to signal that a pre-roll ad should play.
    ///
    /// - Parameter video: The original BCOVVideo
    /// - Returns: A new BCOVVideo with the pre-roll cue point added
    private static func addPreRollCuePoint(to video: BCOVVideo) -> BCOVVideo {
        // Create a pre-roll cue point at time 0
        // Note: "ad" is the standard type for advertising cue points
        let cuePoint = BCOVCuePoint(
            withType: "ad",
            position: CMTime.zero
        )

        // Get existing cue points - cuePoints property is not optional
        let existingCuePoints = (video.cuePoints?.array as? [BCOVCuePoint]) ?? [BCOVCuePoint]()
        var allCuePoints = existingCuePoints

        // Add pre-roll if not already present
        let hasPreRoll = allCuePoints.contains { existingCuePoint in
            existingCuePoint.position == CMTime.zero &&
            existingCuePoint.type == "ad"
        }

        if !hasPreRoll {
            allCuePoints.insert(cuePoint, at: 0)
        }

        // Create new cue point collection
        let cuePointCollection = BCOVCuePointCollection(withArray: allCuePoints)

        // Create new video with updated cue points
        return video.update { mutableVideo in
            mutableVideo.cuePoints = cuePointCollection
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
                // Uses default ad tag (kDefaultIMAAdTagURL)
                video: video1
            ),
            AVIMAVideoItem(
                id: "sample-2",
                name: "Sample Video with Mid-roll",
                description: "Demonstrates mid-roll ad insertion at cue points",
                thumbnailURL: nil,
                duration: 180,
                // Uses default ad tag (kDefaultIMAAdTagURL)
                video: video2
            ),
            AVIMAVideoItem(
                id: "sample-3",
                name: "Sample Video with Skippable Ads",
                description: "Demonstrates skippable ad functionality",
                thumbnailURL: nil,
                duration: 150,
                // Uses default ad tag (kDefaultIMAAdTagURL)
                video: video3
            )
        ]
    }()
}
