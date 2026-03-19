//
//  VideoListItem.swift
//  SwiftUIPlayer
//
//  Copyright © 2024 Brightcove, Inc. All rights reserved.
//

import Foundation
import BrightcovePlayerSDK


struct VideoListItem: Identifiable, Hashable {
    let id: String
    let name: String
    let video: BCOVVideo

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: VideoListItem, rhs: VideoListItem) -> Bool {
        lhs.id == rhs.id
    }
}
