//
//  CachingPlayerItemExtension.swift
//  CachingPlayerItem_Example
//
//  Created by Gorjan Shukov on 10/24/20.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import CachingPlayerItem

// Example `CachingPlayerItem` extension for using custom models.
extension CachingPlayerItem {
    var playable: Playable? {
        passOnObject as? Playable
    }

    convenience init(model: Playable) {
        let saveFilePath = model.saveFilePath
        
        if FileManager.default.fileExists(atPath: saveFilePath.path) {
            self.init(filePathURL: saveFilePath)
            print("Playing from cached local file.")
        } else {
            self.init(url: model.streamURL, saveFilePath: saveFilePath.path, customFileExtension: model.fileExtension)
            print("Playing from remote url.")
        }

        self.passOnObject = model
    }
}
