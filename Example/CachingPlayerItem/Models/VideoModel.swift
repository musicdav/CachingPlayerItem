//
//  VideoModel.swift
//  CachingPlayerItem_Example
//
//  Created by Gorjan Shukov on 10/24/20.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import Foundation

struct VideoModel: Playable {
    let id: String
    let streamURL: URL
    let fileExtension: String
    let thumbnailURL: URL
    var saveFilePath: URL {
        var saveFilePath = try! FileManager.default.url(for: .cachesDirectory,
                                                        in: .userDomainMask,
                                                        appropriateFor: nil,
                                                        create: true)
        saveFilePath.appendPathComponent(id)
        saveFilePath.appendPathExtension(fileExtension)

        return saveFilePath
    }
}
