//
//  SingleMediaViewController.swift
//  CachingPlayerItem
//
//  Created by Gorjan Shukov on 10.10.25.
//  Copyright © 2025 CocoaPods. All rights reserved.
//

import UIKit
import AVKit
import CachingPlayerItem

final class SingleMediaViewController: UIViewController {
    private var player: AVPlayer?
    private lazy var downloadProgressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.trackTintColor = UIColor(white: 1, alpha: 0)
        progressView.progressTintColor = .blue
        progressView.frame = CGRect(x: 0,
                                    y: (navigationController?.navigationBar.frame.size.height ?? 0) - progressView.frame.size.height,
                                    width: (navigationController?.navigationBar.frame.size.width ?? 0),
                                    height: progressView.frame.size.height)
        return progressView
    }()
    private var video = VideoModel(id: "1",
                                   streamURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!,
                                   fileExtension: "mp4",
                                   thumbnailURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/c/c5/Big_buck_bunny_poster_big.jpg")!)
    private var playerLayer: AVPlayerLayer?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Single Media File"
        view.backgroundColor = .systemBackground

        setupPlayer()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.navigationBar.addSubview(downloadProgressView)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        downloadProgressView.removeFromSuperview()
    }

    private func setupPlayer() {
        let cachingItem = CachingPlayerItem(model: video)
        cachingItem.delegate = self
        player = AVPlayer(playerItem: cachingItem)

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.frame = view.bounds
        view.layer.addSublayer(playerLayer)
        self.playerLayer = playerLayer

        player?.play()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        playerLayer?.frame = view.bounds
    }

    func animateProgressViewToCompletion() {
        UIView.animate(withDuration: 0.3, delay: 0.4, options: .curveEaseOut, animations: {
            self.downloadProgressView.alpha = 0
        }, completion: { _ in
            self.downloadProgressView.setProgress(0, animated: false)
        })
    }
}

// MARK: - CachingPlayerItemDelegate

extension SingleMediaViewController: CachingPlayerItemDelegate {
    func playerItemReadyToPlay(_ playerItem: CachingPlayerItem) {
        guard let video = playerItem.playable as? VideoModel else { return }

        print("Caching player item ready to play for \(video.id).")
    }

    func playerItemDidFailToPlay(_ playerItem: CachingPlayerItem, withError error: Error?) {
        guard let _ = playerItem.playable as? VideoModel else { return }

        print(error?.localizedDescription ?? "")
    }

    func playerItemPlaybackStalled(_ playerItem: CachingPlayerItem) {
        print("Caching player item stalled.")
    }

    func playerItem(_ playerItem: CachingPlayerItem, didDownloadBytesSoFar bytesDownloaded: Int, outOf bytesExpected: Int) {
        downloadProgressView.alpha = 1.0
        downloadProgressView.setProgress(Float(Double(bytesDownloaded) / Double(bytesExpected)), animated: true)
    }

    func playerItem(_ playerItem: CachingPlayerItem, didFinishDownloadingFileAt filePath: String) {
        animateProgressViewToCompletion()

        print("Caching player item file downloaded.")
    }

    func playerItem(_ playerItem: CachingPlayerItem, downloadingFailedWith error: Error) {
        animateProgressViewToCompletion()

        print("Caching player item file download failed with error: \(error.localizedDescription).")
    }
}
