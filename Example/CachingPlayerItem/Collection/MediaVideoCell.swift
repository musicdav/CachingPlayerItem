//
//  MediaVideoCell.swift
//  CachingPlayerItem
//
//  Created by Gorjan Shukov on 10.10.25.
//  Copyright © 2025 CocoaPods. All rights reserved.
//

import UIKit
import AVKit
import CachingPlayerItem

final class MediaVideoCell: UICollectionViewCell {
    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var item: CachingPlayerItem?
    private var playingTypeLabel: UILabel!

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true

        playingTypeLabel = UILabel()
        playingTypeLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        playingTypeLabel.textColor = .white
        playingTypeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        playingTypeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(playingTypeLabel)

        NSLayoutConstraint.activate([
            playingTypeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -3),
            playingTypeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with videoModel: VideoModel) {
        let item = CachingPlayerItem(model: videoModel)
        let player = AVPlayer(playerItem: item)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = contentView.bounds

        contentView.layer.addSublayer(layer)
        self.item = item
        self.playerLayer = layer
        self.player = player

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(loopVideo(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )

        player.isMuted = true
        player.play()

        contentView.bringSubviewToFront(playingTypeLabel)
        playingTypeLabel.text = videoModel.isCached ? "Cached" : "Streaming"
    }

    @objc private func loopVideo(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem else { return }

        item.seek(to: .zero, completionHandler: nil)
        player?.play()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        playerLayer?.frame = contentView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)

        if item?.isCaching == true {
            // This is just for demonstration purposes, otherwise not required on this example since it will cancel download on deinit.
            item?.cancelDownload()
        }

        item = nil // will call cancelDownload() automatically if needed
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
    }
}
