//
//  MediaCollectionViewController.swift
//  CachingPlayerItem
//
//  Created by Gorjan Shukov on 10.10.25.
//  Copyright © 2025 CocoaPods. All rights reserved.
//

import UIKit
import CachingPlayerItem

final class MediaCollectionViewController: UICollectionViewController {
    private let reuseIdentifier = "VideoCell"

    private let sampleVideos = [
        VideoModel(id: "BigBuckBunny",
                   streamURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!,
                   fileExtension: "mp4",
                   thumbnailURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg")!),

        VideoModel(id: "ElephantsDream",
                   streamURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4")!,
                   fileExtension: "mp4",
                   thumbnailURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ElephantsDream.jpg")!),

        VideoModel(id: "ForBiggerBlazes",
                   streamURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4")!,
                   fileExtension: "mp4",
                   thumbnailURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerBlazes.jpg")!),

        VideoModel(id: "ForBiggerEscape",
                   streamURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4")!,
                   fileExtension: "mp4",
                   thumbnailURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerEscapes.jpg")!),

        VideoModel(id: "ForBiggerFun",
                   streamURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4")!,
                   fileExtension: "mp4",
                   thumbnailURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerFun.jpg")!),

        VideoModel(id: "ForBiggerJoyrides",
                   streamURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4")!,
                   fileExtension: "mp4",
                   thumbnailURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerJoyrides.jpg")!),

        VideoModel(id: "ForBiggerMeltdowns",
                   streamURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4")!,
                   fileExtension: "mp4",
                   thumbnailURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerMeltdowns.jpg")!),

        VideoModel(id: "Sintel",
                   streamURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4")!,
                   fileExtension: "mp4",
                   thumbnailURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/Sintel.jpg")!),

        VideoModel(id: "SubaruOutbackOnStreetAndDirt",
                   streamURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/SubaruOutbackOnStreetAndDirt.mp4")!,
                   fileExtension: "mp4",
                   thumbnailURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/SubaruOutbackOnStreetAndDirt.jpg")!),

        VideoModel(id: "TearsOfSteel",
                   streamURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4")!,
                   fileExtension: "mp4",
                   thumbnailURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/TearsOfSteel.jpg")!),

        VideoModel(id: "VolkswagenGTIReview",
                   streamURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/VolkswagenGTIReview.mp4")!,
                   fileExtension: "mp4",
                   thumbnailURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/VolkswagenGTIReview.jpg")!),

        VideoModel(id: "WeAreGoingOnBullrun",
                   streamURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WeAreGoingOnBullrun.mp4")!,
                   fileExtension: "mp4",
                   thumbnailURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/WeAreGoingOnBullrun.jpg")!),

        VideoModel(id: "WhatCarCanYouGetForAGrand",
                   streamURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WhatCarCanYouGetForAGrand.mp4")!,
                   fileExtension: "mp4",
                   thumbnailURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/WhatCarCanYouGetForAGrand.jpg")!)
    ]

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Media Collection Grid"
        collectionView.backgroundColor = .systemBackground
        collectionView.register(MediaVideoCell.self, forCellWithReuseIdentifier: reuseIdentifier)
    }

    // MARK: - Data Source

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        20
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as! MediaVideoCell
        let videoModel = sampleVideos[indexPath.item % sampleVideos.count]
        cell.configure(with: videoModel)
        return cell
    }
}

extension MediaCollectionViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let spacing: CGFloat = 8
        let columns: CGFloat = 2
        let totalSpacing = (columns - 1) * spacing
        let width = (collectionView.bounds.width - totalSpacing
                     - collectionView.contentInset.left
                     - collectionView.contentInset.right) / columns
        return CGSize(width: width, height: width)
    }
}
